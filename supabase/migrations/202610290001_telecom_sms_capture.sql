-- 電信代收簡訊 → 待確認收件匣 → LINE 確認入帳.
--
-- A Shortcuts「訊息」automation forwards the carrier's 代收 SMS (遠傳
-- 「Apple商店交易成功通知」) to line-pay-screenshot-ingest as it arrives. It is
-- stored as a telecomBill capture with external_ref telecom-sms:<訂單編號>,
-- dated on arrival since the SMS has no time.
--
-- The same charge shows up a month later in the bill's 代收服務明細, whose rows
-- carry ref telecom:<time to the second>:<amount>. capture_ingest now pairs
-- such a row with the earliest SMS capture of the same amount that arrived
-- between a minute before and 30 minutes after it, instead of capturing the
-- charge twice.
--
-- Everything in this migration is service-role only.

-- Same as before; a telecom bill row pairs with its earlier SMS capture.
create or replace function public.capture_ingest(
  p_token_hash text,
  p_amount_minor bigint,
  p_currency text,
  p_merchant text,
  p_card_label text,
  p_occurred_at timestamptz default now(),
  p_source text default 'applePay',
  p_external_ref text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid;
  merchant_value text :=
    left(trim(regexp_replace(coalesce(p_merchant, ''), '\s+', ' ', 'g')), 80);
  label_value text :=
    left(trim(regexp_replace(coalesce(p_card_label, ''), '\s+', ' ', 'g')), 80);
  currency_value text := upper(coalesce(nullif(trim(p_currency), ''), 'TWD'));
  occurred timestamptz := coalesce(p_occurred_at, now());
  source_value text := coalesce(p_source, 'applePay');
  ref_value text := nullif(left(trim(coalesce(p_external_ref, '')), 200), '');
  existing_id uuid;
  new_id uuid;
  matched_card text;
  matched_account text;
  matched_resolution text;
  line_user text;
begin
  select t.user_id into uid from public.capture_tokens t
  where t.token_hash = p_token_hash;
  if uid is null then return jsonb_build_object('status', 'invalid_token'); end if;

  if source_value not in (
    'applePay', 'linePay', 'linePayMoney', 'twPay', 'debitCard', 'telecomBill'
  ) then
    return jsonb_build_object('status', 'invalid_source');
  end if;
  if p_amount_minor is null or p_amount_minor <= 0
    or p_amount_minor > 999999999999 then
    return jsonb_build_object('status', 'invalid_amount');
  end if;
  if currency_value !~ '^[A-Z]{3}$' then currency_value := 'TWD'; end if;
  -- Shortcuts sends the phone's clock and emails carry the bank's; refuse
  -- obviously wrong timestamps. A telecom bill lists a month or more.
  if occurred > now() + interval '10 minutes'
    or occurred < now() - (case when source_value = 'telecomBill'
      then interval '120 days' else interval '30 days' end) then
    occurred := now();
  end if;

  if (select count(*) from public.capture_inbox i
      where i.user_id = uid and i.created_at > now() - interval '1 hour') >= 60 then
    return jsonb_build_object('status', 'rate_limited');
  end if;

  update public.capture_tokens set last_used_at = now() where user_id = uid;

  if ref_value is not null then
    select i.id into existing_id from public.capture_inbox i
    where i.user_id = uid and i.source = source_value
      and i.external_ref = ref_value;
    if existing_id is not null then
      return jsonb_build_object('status', 'duplicate', 'inboxId', existing_id);
    end if;
  end if;

  -- A retried Shortcut run, a double-fired automation or a bank that sends
  -- the same notice twice is not a second purchase. A telecom bill lists
  -- each charge to the second, so its external_ref is enough.
  select i.id into existing_id from public.capture_inbox i
  where i.user_id = uid and i.source = source_value
    and source_value <> 'telecomBill'
    and i.amount_minor = p_amount_minor
    and i.currency = currency_value and i.merchant = merchant_value
    and i.card_label = label_value
    and i.occurred_at between occurred - interval '2 minutes'
                          and occurred + interval '2 minutes'
  order by i.created_at desc limit 1;
  if existing_id is not null then
    return jsonb_build_object('status', 'duplicate', 'inboxId', existing_id);
  end if;

  -- A bill row is the charge its 代收 SMS announced weeks earlier; the SMS
  -- capture is dated when it arrived, shortly after the purchase. The bill
  -- row takes over the earliest unpaired SMS capture's ref, so the next
  -- same-priced row pairs with the next SMS and a second screenshot of the
  -- bill hits the ref check above.
  if source_value = 'telecomBill' and ref_value like 'telecom:%' then
    select i.id into existing_id from public.capture_inbox i
    where i.user_id = uid and i.source = 'telecomBill'
      and i.external_ref like 'telecom-sms:%'
      and i.amount_minor = p_amount_minor and i.currency = currency_value
      and i.occurred_at between occurred - interval '1 minute'
                            and occurred + interval '30 minutes'
    order by i.occurred_at limit 1
    for update;
    if existing_id is not null then
      update public.capture_inbox set external_ref = ref_value
      where id = existing_id;
      return jsonb_build_object('status', 'duplicate', 'inboxId', existing_id);
    end if;
  end if;

  -- A debit card in Apple Wallet produces both an Apple Pay tap and the
  -- bank's debit notice for one purchase; the tap arrives first.
  if source_value = 'debitCard' then
    select i.id into existing_id from public.capture_inbox i
    where i.user_id = uid and i.source = 'applePay'
      and i.amount_minor = p_amount_minor and i.currency = currency_value
      and i.occurred_at between occurred - interval '10 minutes'
                            and occurred + interval '10 minutes'
    order by i.created_at desc limit 1;
    if existing_id is not null then
      return jsonb_build_object('status', 'duplicate', 'inboxId', existing_id);
    end if;
  end if;

  if source_value = 'telecomBill' then
    -- Booked on the phone bill itself.
    matched_resolution := 'none';
  elsif source_value = 'linePayMoney' then
    -- Only a remembered answer: the label never names a card or account.
    select a.card_id, a.account_id into matched_card, matched_account
    from public.capture_card_aliases a
    where a.user_id = uid and a.card_label = label_value;
    matched_resolution := case
      when not found then 'unknown'
      when matched_card is not null then 'card'
      when matched_account is not null then 'account'
      else 'none'
    end;
  elsif public.capture_uses_account(source_value) then
    select m.account_id, m.resolution into matched_account, matched_resolution
    from public.capture_match_account(uid, label_value) m;
  else
    select m.card_id, m.resolution into matched_card, matched_resolution
    from public.capture_match_card(uid, label_value) m;
  end if;
  begin
    insert into public.capture_inbox(
      user_id, source, external_ref, amount_minor, currency, merchant,
      card_label, card_id, account_id, card_resolution, occurred_at
    ) values (
      uid, source_value, ref_value, p_amount_minor, currency_value,
      merchant_value, label_value, matched_card, matched_account,
      matched_resolution, occurred
    ) returning id into new_id;
  exception when unique_violation then
    -- Two deliveries of the same email raced past the lookup above.
    select i.id into existing_id from public.capture_inbox i
    where i.user_id = uid and i.source = source_value
      and i.external_ref = ref_value;
    return jsonb_build_object('status', 'duplicate', 'inboxId', existing_id);
  end;

  select l.line_user_id into line_user from public.line_account_links l
  where l.user_id = uid and l.enabled;

  return jsonb_build_object(
    'status', 'created',
    'lineUserId', line_user,
    'capture', public.capture_descriptor(new_id)
  );
end
$$;

do $$
declare
  signature text;
begin
  foreach signature in array array[
    'capture_ingest(text,bigint,text,text,text,timestamptz,text,text)'
  ]
  loop
    execute format(
      'revoke all on function public.%s from public, anon, authenticated',
      signature
    );
    execute format('grant execute on function public.%s to service_role', signature);
  end loop;
end
$$;
