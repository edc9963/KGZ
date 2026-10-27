-- LINE Pay 刷卡通知信 → 待確認收件匣 → LINE 確認入帳.
--
-- LINE Pay has no consumer API and no Shortcuts trigger, but when it charges
-- a bound credit card the issuing bank emails a transaction notice. A Gmail
-- Apps Script forwards those emails to the card-email-ingest Edge Function
-- (same per-user capture token as apple-pay-ingest), which parses them and
-- stores LINE Pay charges here with source = 'linePay'. Confirmation reuses
-- the Apple Pay flow (line_capture_confirm).
--
-- Everything in this migration is service-role only.

alter table public.capture_inbox
  drop constraint capture_inbox_source_check;
alter table public.capture_inbox
  add constraint capture_inbox_source_check
  check (source in ('applePay', 'linePay'));

-- Upstream id of the event (the email Message-ID), so a re-sent email is
-- recognised even when its parsed fields differ slightly.
alter table public.capture_inbox
  add column external_ref text
  check (external_ref is null or char_length(external_ref) between 1 and 200);

create unique index capture_inbox_external_ref_idx
  on public.capture_inbox(user_id, source, external_ref)
  where external_ref is not null;

drop function public.capture_ingest(text, bigint, text, text, text, timestamptz);

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
  matched record;
  line_user text;
begin
  select t.user_id into uid from public.capture_tokens t
  where t.token_hash = p_token_hash;
  if uid is null then return jsonb_build_object('status', 'invalid_token'); end if;

  if source_value not in ('applePay', 'linePay') then
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

  select * into matched from public.capture_match_card(uid, label_value);
  begin
    insert into public.capture_inbox(
      user_id, source, external_ref, amount_minor, currency, merchant,
      card_label, card_id, card_resolution, occurred_at
    ) values (
      uid, source_value, ref_value, p_amount_minor, currency_value,
      merchant_value, label_value, matched.card_id, matched.resolution, occurred
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

-- Same as before, plus the source so LINE can say Apple Pay or LINE Pay.
create or replace function public.capture_descriptor(p_inbox_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  row_data public.capture_inbox;
  categories jsonb;
  suggested_name text;
  suggested_id text;
  card_name text;
  card_last_four text;
begin
  select * into row_data from public.capture_inbox where id = p_inbox_id;
  if not found then return null; end if;
  categories := public.capture_expense_categories(row_data.user_id);

  -- Learn from history: the category last used for this merchant.
  if row_data.merchant <> '' then
    select e.category into suggested_name from public.expenses e
    where e.user_id = row_data.user_id
      and lower(trim(e.merchant)) = lower(row_data.merchant)
    order by e.expense_date desc limit 1;
  end if;
  if suggested_name is not null then
    select item->>'id' into suggested_id
    from jsonb_array_elements(categories) item
    where lower(trim(item->>'name')) = lower(trim(suggested_name))
    limit 1;
  end if;

  if row_data.card_id is not null then
    select c.name, c.last_four into card_name, card_last_four
    from public.credit_cards c
    where c.user_id = row_data.user_id and c.id = row_data.card_id;
  end if;

  return jsonb_build_object(
    'inboxId', row_data.id,
    'source', row_data.source,
    'status', row_data.status,
    'amountMinor', row_data.amount_minor,
    'currency', row_data.currency,
    'merchant', row_data.merchant,
    'cardLabel', row_data.card_label,
    'cardResolution', row_data.card_resolution,
    'cardName', card_name,
    'cardLastFour', card_last_four,
    'occurredAt', row_data.occurred_at,
    'suggestedCategoryId', suggested_id,
    'categories', categories
  );
end
$$;

create or replace function public.line_capture_list_pending(p_line_user_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := public.line_linked_owner_id(p_line_user_id);
begin
  if uid is null then return jsonb_build_object('status', 'not_linked'); end if;
  return jsonb_build_object(
    'status', 'ok',
    'total', (select count(*) from public.capture_inbox i
              where i.user_id = uid and i.status = 'pending'),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'inboxId', p.id, 'source', p.source, 'amountMinor', p.amount_minor,
        'currency', p.currency, 'merchant', p.merchant,
        'occurredAt', p.occurred_at
      ) order by p.occurred_at desc)
      from (
        select * from public.capture_inbox i
        where i.user_id = uid and i.status = 'pending'
        order by i.occurred_at desc limit 12
      ) p
    ), '[]'::jsonb)
  );
end
$$;

-- Same as before; the fallback item text, note and card question now follow
-- the inbox row's source.
create or replace function public.line_capture_confirm(
  p_line_user_id text,
  p_inbox_id uuid,
  p_category_id text default null,
  p_card_choice text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := public.line_linked_owner_id(p_line_user_id);
  row_data public.capture_inbox;
  category_id text;
  category_name text;
  effective_card text;
  effective_resolution text;
  card_type text;
  card_name text;
  method text;
  item_text text;
  note_text text;
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

  if p_card_choice is not null then
    if p_card_choice = '__none__' then
      effective_card := null;
      effective_resolution := 'none';
    else
      if not exists (
        select 1 from public.credit_cards c
        where c.user_id = uid and c.id = p_card_choice and c.is_active
      ) then
        return jsonb_build_object('status', 'invalid_card');
      end if;
      effective_card := p_card_choice;
      effective_resolution := 'card';
    end if;
    if row_data.card_label <> '' then
      insert into public.capture_card_aliases(user_id, card_label, card_id, updated_at)
      values (uid, row_data.card_label, effective_card, now())
      on conflict (user_id, card_label) do update
      set card_id = excluded.card_id, updated_at = now();
    end if;
  else
    effective_card := row_data.card_id;
    effective_resolution := row_data.card_resolution;
    -- The matched card may have been deactivated since the tap.
    if effective_resolution = 'card' and not exists (
      select 1 from public.credit_cards c
      where c.user_id = uid and c.id = effective_card and c.is_active
    ) then
      effective_card := null;
      effective_resolution := 'unknown';
    end if;
  end if;

  if effective_resolution = 'unknown' then
    update public.capture_inbox
    set pending_category_id = category_id, card_id = null,
        card_resolution = 'unknown'
    where id = row_data.id;
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
  else
    method := 'other';
  end if;

  if row_data.source = 'linePay' then
    item_text := coalesce(nullif(row_data.merchant, ''), 'LINE Pay 消費');
    note_text := 'LINE Pay 刷卡通知建立';
  else
    item_text := coalesce(nullif(row_data.merchant, ''), 'Apple Pay 消費');
    note_text := 'Apple Pay 捷徑建立';
  end if;
  saved := public.line_confirm_expense(
    p_line_user_id, row_data.id, row_data.amount_minor, item_text,
    category_name, method, null, effective_card, row_data.occurred_at
  );
  if saved->>'status' <> 'saved' then return saved; end if;

  update public.expenses
  set merchant = row_data.merchant, note = note_text
  where user_id = uid and id = saved->>'expenseId';

  update public.capture_inbox
  set status = 'confirmed', expense_id = saved->>'expenseId',
      card_id = effective_card, card_resolution = effective_resolution,
      pending_category_id = null, resolved_at = now()
  where id = row_data.id;

  return jsonb_build_object(
    'status', 'saved',
    'duplicate', coalesce((saved->>'duplicate')::boolean, false),
    'amountMinor', row_data.amount_minor,
    'merchant', item_text,
    'category', category_name,
    'cardName', card_name
  );
end
$$;

do $$
declare
  signature text;
begin
  foreach signature in array array[
    'capture_ingest(text,bigint,text,text,text,timestamptz,text,text)',
    'capture_descriptor(uuid)',
    'line_capture_list_pending(text)',
    'line_capture_confirm(text,uuid,text,text)'
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
