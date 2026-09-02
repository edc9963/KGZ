-- Keep LINE quick-entry payment choices aligned with the web application.
-- Only active asset accounts are selectable, and debit-card expenses use the
-- account bound to the selected managed debit card.

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
    'telecomBillConfigured', exists(
      select 1
      from public.recurring_expenses recurring
      join public.accounts account
        on account.user_id = recurring.user_id
       and account.id = recurring.telecom_debit_account_id
      left join public.financial_account_metadata metadata
        on metadata.user_id = account.user_id and metadata.account_id = account.id
      where recurring.user_id = uid and recurring.is_active
        and recurring.payment_method = 'telecomBill' and account.is_active
        and coalesce(metadata.account_kind, 'asset') = 'asset'
    ),
    'accounts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', a.id, 'name', a.name, 'currency', a.currency
      ) order by a.name, a.id)
      from public.accounts a
      left join public.financial_account_metadata metadata
        on metadata.user_id = a.user_id and metadata.account_id = a.id
      where a.user_id = uid and a.is_active
        and coalesce(metadata.account_kind, 'asset') = 'asset'
    ), '[]'::jsonb),
    'cards', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', card.id, 'name', card.name, 'lastFour', card.last_four,
        'cardType', coalesce(profile.card_type, 'credit'),
        'debitAccountId', card.debit_account_id
      ) order by card.name, card.id)
      from public.credit_cards card
      left join public.payment_card_profiles profile
        on profile.user_id = card.user_id and profile.card_id = card.id
      where card.user_id = uid and card.is_active
    ), '[]'::jsonb)
  );
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
  selected_card_type text;
  selected_card_account_id text;
  effective_account_id text := p_account_id;
  effective_card_id text := p_card_id;
begin
  if uid is null then return jsonb_build_object('status', 'not_linked'); end if;
  select command.result into prior from public.line_finance_commands command
  where command.command_id = p_command_id and command.user_id = uid;
  if prior is not null then return prior || jsonb_build_object('duplicate', true); end if;

  if p_amount_minor <= 0 or p_amount_minor > 999999999999 then
    raise exception 'invalid_amount';
  end if;
  if char_length(trim(p_item)) not between 1 and 80 then
    raise exception 'invalid_item';
  end if;
  if p_payment_method not in (
    'cash', 'transfer', 'debitCard', 'creditCard', 'linePay',
    'jkoPay', 'easyCard', 'iPass', 'telecomBill', 'other'
  ) then raise exception 'invalid_payment_method'; end if;

  if p_payment_method in ('creditCard', 'debitCard') then
    if p_card_id is null then raise exception 'card_required'; end if;
    select coalesce(profile.card_type, 'credit'), card.debit_account_id
      into selected_card_type, selected_card_account_id
    from public.credit_cards card
    left join public.payment_card_profiles profile
      on profile.user_id = card.user_id and profile.card_id = card.id
    where card.user_id = uid and card.id = p_card_id and card.is_active;
    if not found then raise exception 'invalid_card'; end if;
    if (p_payment_method = 'creditCard' and selected_card_type <> 'credit')
      or (p_payment_method = 'debitCard' and selected_card_type <> 'debit') then
      raise exception 'invalid_card_type';
    end if;
    effective_account_id := case
      when p_payment_method = 'debitCard' then selected_card_account_id
      else null
    end;
  else
    effective_card_id := null;
  end if;

  if p_payment_method = 'telecomBill' then
    effective_account_id := null;
    if not exists (
      select 1
      from public.recurring_expenses recurring
      join public.accounts account
        on account.user_id = recurring.user_id
       and account.id = recurring.telecom_debit_account_id
      left join public.financial_account_metadata metadata
        on metadata.user_id = account.user_id and metadata.account_id = account.id
      where recurring.user_id = uid and recurring.is_active
        and recurring.payment_method = 'telecomBill' and account.is_active
        and coalesce(metadata.account_kind, 'asset') = 'asset'
    ) then raise exception 'telecom_bill_not_configured'; end if;
  end if;

  if p_payment_method = 'transfer' and effective_account_id is null then
    raise exception 'account_required';
  end if;
  if effective_account_id is not null and not exists (
    select 1 from public.accounts account
    left join public.financial_account_metadata metadata
      on metadata.user_id = account.user_id and metadata.account_id = account.id
    where account.user_id = uid and account.id = effective_account_id
      and account.is_active
      and coalesce(metadata.account_kind, 'asset') = 'asset'
  ) then raise exception 'invalid_account'; end if;

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
    effective_account_id, effective_card_id, '', 'LINE 官方帳號建立', false, 'user'
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
