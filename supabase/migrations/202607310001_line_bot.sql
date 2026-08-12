-- LINE Official Account integration. All functions in this migration are
-- server-only: the webhook calls them with the service-role key and clients
-- continue to use the revisioned snapshot RPCs.

create table public.line_account_links (
  user_id uuid primary key references auth.users(id) on delete cascade,
  line_user_id text not null unique,
  enabled boolean not null default true,
  consented_at timestamptz not null default now(),
  linked_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.line_webhook_events (
  webhook_event_id text primary key,
  line_user_id text,
  event_type text not null,
  status text not null default 'processing'
    check (status in ('processing', 'completed', 'ignored', 'failed')),
  error_code text,
  received_at timestamptz not null default now(),
  processed_at timestamptz
);

create table public.line_conversations (
  line_user_id text primary key,
  flow text not null,
  step text not null,
  payload jsonb not null default '{}'::jsonb,
  expires_at timestamptz not null,
  updated_at timestamptz not null default now()
);

create table public.line_action_tokens (
  token uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  line_user_id text not null,
  action text not null,
  payload jsonb not null,
  expires_at timestamptz not null default (now() + interval '15 minutes'),
  consumed_at timestamptz
);

create table public.line_finance_commands (
  command_id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  command_type text not null,
  result jsonb not null,
  created_at timestamptz not null default now()
);

-- Phase-two OCR schema. The webhook does not write these tables while
-- OCR_ENABLED=false.
create table public.line_import_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  line_user_id text not null,
  status text not null default 'collecting'
    check (status in (
      'collecting', 'queued', 'processing', 'review', 'confirmed',
      'cancelled', 'failed', 'expired'
    )),
  review_token_hash text unique,
  review_token_expires_at timestamptz,
  draft jsonb,
  error_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '24 hours')
);

create table public.line_import_images (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.line_import_sessions(id)
    on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  storage_path text not null unique,
  byte_size integer not null check (byte_size > 0 and byte_size <= 6291456),
  position integer not null check (position between 0 and 5),
  created_at timestamptz not null default now(),
  unique (session_id, position)
);

create table public.line_ocr_jobs (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null unique references public.line_import_sessions(id)
    on delete cascade,
  status text not null default 'queued'
    check (status in ('queued', 'processing', 'completed', 'failed')),
  attempts integer not null default 0 check (attempts between 0 and 5),
  callback_nonce_hash text not null,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz
);

create index line_action_tokens_lookup_idx
  on public.line_action_tokens(line_user_id, action, expires_at);
create index line_import_sessions_expiry_idx
  on public.line_import_sessions(expires_at);

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'line_account_links', 'line_webhook_events', 'line_conversations',
    'line_action_tokens', 'line_finance_commands', 'line_import_sessions',
    'line_import_images', 'line_ocr_jobs'
  ]
  loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('revoke all on public.%I from anon, authenticated', table_name);
  end loop;
end
$$;

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values (
  'line-imports',
  'line-imports',
  false,
  6291456,
  array['image/png', 'image/jpeg', 'image/webp']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.line_owner_id(p_line_user_id text)
returns uuid
language sql
stable
security definer
set search_path = public, auth, pg_temp
as $$
  select i.user_id
  from auth.identities i
  where i.provider_id = p_line_user_id
  order by i.created_at
  limit 1
$$;

create or replace function public.line_linked_owner_id(p_line_user_id text)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select l.user_id
  from public.line_account_links l
  where l.line_user_id = p_line_user_id and l.enabled
$$;

create or replace function public.line_resolve_identity(p_line_user_id text)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  owner_id uuid;
  linked_id uuid;
begin
  if nullif(trim(p_line_user_id), '') is null then
    raise exception 'invalid_line_user_id';
  end if;
  owner_id := public.line_owner_id(p_line_user_id);
  linked_id := public.line_linked_owner_id(p_line_user_id);
  return jsonb_build_object(
    'status', case
      when linked_id is not null then 'linked'
      when owner_id is not null then 'available'
      else 'unknown'
    end
  );
end
$$;

create or replace function public.line_link_account(p_line_user_id text)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  owner_id uuid := public.line_owner_id(p_line_user_id);
begin
  if owner_id is null then
    return jsonb_build_object('status', 'unknown');
  end if;
  insert into public.line_account_links(user_id, line_user_id)
  values (owner_id, p_line_user_id)
  on conflict (user_id) do update
    set line_user_id = excluded.line_user_id,
        enabled = true,
        consented_at = now(),
        updated_at = now();
  return jsonb_build_object('status', 'linked');
end
$$;

create or replace function public.line_finance_summary(p_line_user_id text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := public.line_linked_owner_id(p_line_user_id);
  result jsonb;
begin
  if uid is null then return jsonb_build_object('status', 'not_linked'); end if;

  with account_total as (
    select coalesce(sum(a.opening_balance_minor), 0)
      + coalesce((select sum(x.amount_minor)
                  from public.balance_adjustments x where x.user_id = uid), 0)
      - coalesce((select sum(e.amount_minor)
                  from public.expenses e
                  where e.user_id = uid and e.account_id is not null
                    and e.payment_method <> 'creditCard'), 0)
      - coalesce((select sum(b.paid_minor)
                  from public.card_bills b where b.user_id = uid), 0)
      + coalesce((
          select sum(coalesce(p.final_due_minor, p.suggested_due_minor,
                     greatest(p.item_amount_minor + p.shared_fee_minor
                              - p.discount_minor, 0)))
          from public.order_participants p
          where p.user_id = uid and not p.is_self
            and p.collection_status = 'paid'
            and p.collection_account_id is not null
        ), 0) as value
    from public.accounts a where a.user_id = uid and a.is_active
  ), month_expense as (
    select
      coalesce((select sum(e.amount_minor) from public.expenses e
                where e.user_id = uid
                  and date_trunc('month', e.expense_date at time zone 'Asia/Taipei')
                      = date_trunc('month', now() at time zone 'Asia/Taipei')), 0)
      + coalesce((
          select sum(greatest(p.item_amount_minor + p.shared_fee_minor
                              - p.discount_minor, 0))
          from public.group_orders o
          join public.order_participants p
            on p.user_id = o.user_id and p.order_id = o.id
          where o.user_id = uid and p.is_self
            and date_trunc('month', o.order_date at time zone 'Asia/Taipei')
                = date_trunc('month', now() at time zone 'Asia/Taipei')
        ), 0) as value
  ), receivables as (
    select coalesce(sum(coalesce(p.final_due_minor, p.suggested_due_minor,
                     greatest(p.item_amount_minor + p.shared_fee_minor
                              - p.discount_minor, 0))), 0) as value
    from public.order_participants p
    where p.user_id = uid and not p.is_self
      and p.collection_status not in ('paid', 'cancelled')
  ), pending_card as (
    select
      coalesce((select sum(e.amount_minor) from public.expenses e
                where e.user_id = uid and e.payment_method = 'creditCard'
                  and not exists (
                    select 1 from public.card_bill_expenses be
                    where be.user_id = uid and be.expense_id = e.id)), 0)
      + coalesce((select sum(o.total_minor) from public.group_orders o
                  where o.user_id = uid and not exists (
                    select 1 from public.card_bill_orders bo
                    where bo.user_id = uid and bo.order_id = o.id)), 0)
      + coalesce((
          select sum(greatest(
            b.manual_adjustment_minor
            + coalesce((select sum(e.amount_minor)
                        from public.card_bill_expenses be
                        join public.expenses e
                          on e.user_id = be.user_id and e.id = be.expense_id
                        where be.user_id = uid and be.bill_id = b.id), 0)
            + coalesce((select sum(o.total_minor)
                        from public.card_bill_orders bo
                        join public.group_orders o
                          on o.user_id = bo.user_id and o.id = bo.order_id
                        where bo.user_id = uid and bo.bill_id = b.id), 0)
            - b.paid_minor, 0))
          from public.card_bills b where b.user_id = uid
        ), 0) as value
  )
  select jsonb_build_object(
    'status', 'ok',
    'accountBalanceMinor', (select value from account_total),
    'monthExpenseMinor', (select value from month_expense),
    'pendingCardMinor', (select value from pending_card),
    'receivablesMinor', (select value from receivables),
    'revision', coalesce((
      select revision from public.finance_sync_state where user_id = uid
    ), 0),
    'updatedAt', (
      select updated_at from public.finance_sync_state where user_id = uid
    )
  ) into result;
  return result;
end
$$;

create or replace function public.line_list_payment_sources(p_line_user_id text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := public.line_linked_owner_id(p_line_user_id);
begin
  if uid is null then return jsonb_build_object('status', 'not_linked'); end if;
  return jsonb_build_object(
    'status', 'ok',
    'defaultPaymentMethod', coalesce((
      select default_payment_method from public.user_settings where user_id = uid
    ), 'creditCard'),
    'defaultCategory', coalesce((
      select default_category from public.user_settings where user_id = uid
    ), '餐飲'),
    'accounts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id, 'name', name, 'currency', currency
      ) order by name)
      from public.accounts where user_id = uid and is_active
    ), '[]'::jsonb),
    'cards', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id, 'name', name, 'lastFour', last_four
      ) order by name)
      from public.credit_cards where user_id = uid and is_active
    ), '[]'::jsonb)
  );
end
$$;

create or replace function public.line_list_receivables(
  p_line_user_id text,
  p_limit integer default 8
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := public.line_linked_owner_id(p_line_user_id);
  items jsonb;
begin
  if uid is null then return jsonb_build_object('status', 'not_linked'); end if;
  p_limit := greatest(1, least(coalesce(p_limit, 8), 10));

  delete from public.line_action_tokens
  where line_user_id = p_line_user_id and expires_at < now();

  with pending as (
    select o.id as order_id, o.name as order_name, p.id as participant_id,
           p.name as participant_name,
           coalesce(p.final_due_minor, p.suggested_due_minor,
                    greatest(p.item_amount_minor + p.shared_fee_minor
                             - p.discount_minor, 0)) as amount_minor
    from public.group_orders o
    join public.order_participants p
      on p.user_id = o.user_id and p.order_id = o.id
    where o.user_id = uid and not p.is_self
      and p.collection_status not in ('paid', 'cancelled')
    order by o.order_date desc, p.id
    limit p_limit
  ), issued as (
    insert into public.line_action_tokens(
      user_id, line_user_id, action, payload
    )
    select uid, p_line_user_id, 'mark_received',
           jsonb_build_object(
             'orderId', order_id, 'participantId', participant_id
           )
    from pending
    returning token, payload
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'token', i.token,
    'orderName', p.order_name,
    'participantName', p.participant_name,
    'amountMinor', p.amount_minor
  ) order by p.order_name, p.participant_name), '[]'::jsonb)
  into items
  from pending p
  join issued i
    on i.payload->>'orderId' = p.order_id
   and i.payload->>'participantId' = p.participant_id;

  return jsonb_build_object('status', 'ok', 'items', items);
end
$$;

create or replace function public.line_confirm_expense(
  p_line_user_id text,
  p_command_id uuid,
  p_amount_minor bigint,
  p_item text,
  p_category text,
  p_payment_method text,
  p_account_id text default null,
  p_card_id text default null,
  p_expense_date timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := public.line_linked_owner_id(p_line_user_id);
  current_revision bigint;
  next_revision bigint;
  expense_id text := 'line-' || gen_random_uuid()::text;
  prior jsonb;
  result jsonb;
begin
  if uid is null then return jsonb_build_object('status', 'not_linked'); end if;
  select c.result into prior from public.line_finance_commands c
  where c.command_id = p_command_id and c.user_id = uid;
  if prior is not null then return prior || jsonb_build_object('duplicate', true); end if;

  if p_amount_minor <= 0 or p_amount_minor > 999999999999 then
    raise exception 'invalid_amount';
  end if;
  if char_length(trim(p_item)) not between 1 and 80 then
    raise exception 'invalid_item';
  end if;
  if p_payment_method not in (
    'cash', 'transfer', 'debitCard', 'creditCard', 'linePay',
    'jkoPay', 'easyCard', 'iPass', 'other'
  ) then raise exception 'invalid_payment_method'; end if;
  if p_account_id is not null and not exists (
    select 1 from public.accounts
    where user_id = uid and id = p_account_id and is_active
  ) then raise exception 'invalid_account'; end if;
  if p_card_id is not null and not exists (
    select 1 from public.credit_cards
    where user_id = uid and id = p_card_id and is_active
  ) then raise exception 'invalid_card'; end if;
  if p_payment_method = 'creditCard' and p_card_id is null then
    raise exception 'card_required';
  end if;

  insert into public.finance_sync_state(user_id, revision)
  values (uid, 0) on conflict (user_id) do nothing;
  select revision into current_revision
  from public.finance_sync_state where user_id = uid for update;

  insert into public.expenses(
    user_id, id, expense_date, amount_minor, payment_method, item, category,
    account_id, card_id, merchant, note, is_necessary, origin
  ) values (
    uid, expense_id, p_expense_date, p_amount_minor, p_payment_method,
    trim(p_item), left(coalesce(nullif(trim(p_category), ''), '其他'), 40),
    p_account_id, p_card_id, '', 'LINE 官方帳號建立', false, 'user'
  );
  next_revision := current_revision + 1;
  update public.finance_sync_state
  set revision = next_revision, updated_at = now() where user_id = uid;
  result := jsonb_build_object(
    'status', 'saved', 'expenseId', expense_id, 'revision', next_revision
  );
  insert into public.line_finance_commands(
    command_id, user_id, command_type, result
  ) values (p_command_id, uid, 'create_expense', result);
  return result;
end
$$;

create or replace function public.line_mark_received(
  p_line_user_id text,
  p_token uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := public.line_linked_owner_id(p_line_user_id);
  action_row public.line_action_tokens%rowtype;
  current_revision bigint;
  next_revision bigint;
  was_paid boolean;
begin
  if uid is null then return jsonb_build_object('status', 'not_linked'); end if;
  select * into action_row from public.line_action_tokens
  where token = p_token and user_id = uid and line_user_id = p_line_user_id
    and action = 'mark_received'
  for update;
  if not found or action_row.expires_at < now() then
    return jsonb_build_object('status', 'expired');
  end if;
  if action_row.consumed_at is not null then
    return jsonb_build_object('status', 'already_processed');
  end if;

  select collection_status = 'paid' into was_paid
  from public.order_participants
  where user_id = uid
    and order_id = action_row.payload->>'orderId'
    and id = action_row.payload->>'participantId'
  for update;
  if not found then return jsonb_build_object('status', 'not_found'); end if;

  update public.line_action_tokens set consumed_at = now()
  where token = p_token;
  if was_paid then return jsonb_build_object('status', 'already_paid'); end if;

  insert into public.finance_sync_state(user_id, revision)
  values (uid, 0) on conflict (user_id) do nothing;
  select revision into current_revision
  from public.finance_sync_state where user_id = uid for update;

  update public.order_participants
  set collection_status = 'paid', collected_at = now()
  where user_id = uid
    and order_id = action_row.payload->>'orderId'
    and id = action_row.payload->>'participantId';
  next_revision := current_revision + 1;
  update public.finance_sync_state
  set revision = next_revision, updated_at = now() where user_id = uid;
  return jsonb_build_object('status', 'saved', 'revision', next_revision);
end
$$;

do $$
declare
  signature text;
begin
  foreach signature in array array[
    'line_owner_id(text)', 'line_linked_owner_id(text)',
    'line_resolve_identity(text)', 'line_link_account(text)',
    'line_finance_summary(text)', 'line_list_payment_sources(text)',
    'line_list_receivables(text,integer)',
    'line_confirm_expense(text,uuid,bigint,text,text,text,text,text,timestamptz)',
    'line_mark_received(text,uuid)'
  ]
  loop
    execute format('revoke all on function public.%s from public', signature);
    execute format('grant execute on function public.%s to service_role', signature);
  end loop;
end
$$;
