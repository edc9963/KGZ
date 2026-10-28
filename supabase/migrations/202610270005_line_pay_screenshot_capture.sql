-- LINE Pay 付款截圖（iOS 從影像擷取文字）→ 待確認收件匣 → LINE 確認入帳.
--
-- LINE Pay sends no email; each payment only shows up as a card in the LINE
-- Pay official account chat. The line-pay-screenshot-ingest function parses
-- the text of a screenshot of that chat. Payments made with the bound credit
-- card come in as linePay (label "LINE Pay", resolved to a card); payments
-- from the LINE Pay Money wallet as the new source linePayMoney (label
-- "LINE Pay Money", resolved to an asset account like TWPAY debits).
--
-- Everything in this migration is service-role only.

alter table public.capture_inbox
  drop constraint capture_inbox_source_check;
alter table public.capture_inbox
  add constraint capture_inbox_source_check
  check (source in ('applePay', 'linePay', 'linePayMoney', 'twPay', 'debitCard'));

create or replace function public.capture_uses_account(p_source text)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$
  select p_source in ('linePayMoney', 'twPay', 'debitCard')
$$;

create or replace function public.capture_source_name(p_source text)
returns text
language sql
immutable
set search_path = public, pg_temp
as $$
  select case p_source
    when 'linePay' then 'LINE Pay'
    when 'linePayMoney' then 'LINE Pay Money'
    when 'twPay' then 'TWPAY'
    when 'debitCard' then '金融卡'
    else 'Apple Pay'
  end
$$;

-- Same as before; accepts linePayMoney.
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
    'applePay', 'linePay', 'linePayMoney', 'twPay', 'debitCard'
  ) then
    return jsonb_build_object('status', 'invalid_source');
  end if;
  if p_amount_minor is null or p_amount_minor <= 0
    or p_amount_minor > 999999999999 then
    return jsonb_build_object('status', 'invalid_amount');
  end if;
  if currency_value !~ '^[A-Z]{3}$' then currency_value := 'TWD'; end if;
  -- Shortcuts sends the phone's clock and emails carry the bank's; refuse
  -- obviously wrong timestamps.
  if occurred > now() + interval '10 minutes'
    or occurred < now() - interval '30 days' then
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
  -- the same notice twice is not a second purchase.
  select i.id into existing_id from public.capture_inbox i
  where i.user_id = uid and i.source = source_value
    and i.amount_minor = p_amount_minor
    and i.currency = currency_value and i.merchant = merchant_value
    and i.card_label = label_value
    and i.occurred_at between occurred - interval '2 minutes'
                          and occurred + interval '2 minutes'
  order by i.created_at desc limit 1;
  if existing_id is not null then
    return jsonb_build_object('status', 'duplicate', 'inboxId', existing_id);
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

  if public.capture_uses_account(source_value) then
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

-- Same as before; the expense note names how the capture arrived.
create or replace function public.line_capture_confirm(
  p_line_user_id text,
  p_inbox_id uuid,
  p_category_id text default null,
  p_card_choice text default null,
  p_account_choice text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := public.line_linked_owner_id(p_line_user_id);
  row_data public.capture_inbox;
  uses_account boolean;
  choice text;
  category_id text;
  category_name text;
  effective_card text;
  effective_account text;
  effective_resolution text;
  card_type text;
  card_name text;
  account_name text;
  method text;
  item_text text;
  saved jsonb;
begin
  if uid is null then return jsonb_build_object('status', 'not_linked'); end if;
  select * into row_data from public.capture_inbox
  where id = p_inbox_id and user_id = uid for update;
  if not found then return jsonb_build_object('status', 'not_found'); end if;
  if row_data.status = 'confirmed' then
    return jsonb_build_object('status', 'already_confirmed');
  end if;
  if row_data.status = 'dismissed' then
    return jsonb_build_object('status', 'already_dismissed');
  end if;
  if row_data.currency <> 'TWD' then
    return jsonb_build_object('status', 'unsupported_currency');
  end if;

  category_id := coalesce(p_category_id, row_data.pending_category_id);
  select item->>'name' into category_name
  from jsonb_array_elements(public.capture_expense_categories(uid)) item
  where item->>'id' = category_id limit 1;
  if category_name is null then
    return jsonb_build_object('status', 'invalid_category');
  end if;

  uses_account := public.capture_uses_account(row_data.source);
  choice := case when uses_account then p_account_choice else p_card_choice end;

  if choice is not null then
    if choice = '__none__' then
      effective_resolution := 'none';
    elsif uses_account then
      if not exists (
        select 1 from jsonb_array_elements(public.capture_active_accounts(uid)) item
        where item->>'id' = choice
      ) then
        return jsonb_build_object('status', 'invalid_account');
      end if;
      effective_account := choice;
      effective_resolution := 'account';
    else
      if not exists (
        select 1 from public.credit_cards c
        where c.user_id = uid and c.id = choice and c.is_active
      ) then
        return jsonb_build_object('status', 'invalid_card');
      end if;
      effective_card := choice;
      effective_resolution := 'card';
    end if;
    if row_data.card_label <> '' then
      insert into public.capture_card_aliases(
        user_id, card_label, card_id, account_id, updated_at
      ) values (uid, row_data.card_label, effective_card, effective_account, now())
      on conflict (user_id, card_label) do update
      set card_id = excluded.card_id, account_id = excluded.account_id,
          updated_at = now();
    end if;
  else
    effective_card := row_data.card_id;
    effective_account := row_data.account_id;
    effective_resolution := row_data.card_resolution;
    -- The matched card or account may have been deactivated since.
    if effective_resolution = 'card' and not exists (
      select 1 from public.credit_cards c
      where c.user_id = uid and c.id = effective_card and c.is_active
    ) then
      effective_card := null;
      effective_resolution := 'unknown';
    end if;
    if effective_resolution = 'account' and not exists (
      select 1 from jsonb_array_elements(public.capture_active_accounts(uid)) item
      where item->>'id' = effective_account
    ) then
      effective_account := null;
      effective_resolution := 'unknown';
    end if;
  end if;

  if effective_resolution = 'unknown' then
    update public.capture_inbox
    set pending_category_id = category_id, card_id = null, account_id = null,
        card_resolution = 'unknown'
    where id = row_data.id;
    if uses_account then
      return jsonb_build_object(
        'status', 'needs_account',
        'source', row_data.source,
        'cardLabel', row_data.card_label,
        'accounts', public.capture_active_accounts(uid)
      );
    end if;
    return jsonb_build_object(
      'status', 'needs_card',
      'source', row_data.source,
      'cardLabel', row_data.card_label,
      'cards', public.capture_active_cards(uid)
    );
  end if;

  if effective_resolution = 'card' then
    select coalesce(p.card_type, 'credit'), c.name into card_type, card_name
    from public.credit_cards c
    left join public.payment_card_profiles p
      on p.user_id = c.user_id and p.card_id = c.id
    where c.user_id = uid and c.id = effective_card;
    method := case when card_type = 'debit' then 'debitCard' else 'creditCard' end;
  elsif effective_resolution = 'account' then
    select a.name into account_name from public.accounts a
    where a.user_id = uid and a.id = effective_account;
    if row_data.source = 'debitCard' then
      effective_card := public.capture_debit_card_for_account(uid, effective_account);
    end if;
    if effective_card is not null then
      method := 'debitCard';
      select c.name into card_name from public.credit_cards c
      where c.user_id = uid and c.id = effective_card;
    else
      method := 'transfer';
    end if;
  else
    method := 'other';
  end if;

  item_text := coalesce(
    nullif(row_data.merchant, ''),
    public.capture_source_name(row_data.source) || ' 消費'
  );
  saved := public.line_confirm_expense(
    p_line_user_id, row_data.id, row_data.amount_minor, item_text,
    category_name, method,
    case when method = 'transfer' then effective_account end,
    case when method in ('creditCard', 'debitCard') then effective_card end,
    row_data.occurred_at
  );
  if saved->>'status' <> 'saved' then return saved; end if;

  update public.expenses
  set merchant = row_data.merchant,
      note = case row_data.source
        when 'linePay' then 'LINE Pay 自動記帳建立'
        when 'linePayMoney' then 'LINE Pay Money 自動記帳建立'
        when 'twPay' then 'TWPAY 扣帳通知建立'
        when 'debitCard' then '金融卡扣帳通知建立'
        else 'Apple Pay 捷徑建立'
      end
  where user_id = uid and id = saved->>'expenseId';

  update public.capture_inbox
  set status = 'confirmed', expense_id = saved->>'expenseId',
      card_id = effective_card, account_id = effective_account,
      card_resolution = effective_resolution,
      pending_category_id = null, resolved_at = now()
  where id = row_data.id;

  return jsonb_build_object(
    'status', 'saved',
    'duplicate', coalesce((saved->>'duplicate')::boolean, false),
    'amountMinor', row_data.amount_minor,
    'merchant', item_text,
    'category', category_name,
    'cardName', coalesce(card_name, account_name)
  );
end
$$;

do $$
declare
  signature text;
begin
  foreach signature in array array[
    'capture_uses_account(text)',
    'capture_source_name(text)',
    'capture_ingest(text,bigint,text,text,text,timestamptz,text,text)',
    'line_capture_confirm(text,uuid,text,text,text)'
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
