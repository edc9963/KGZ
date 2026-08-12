-- Cloud-backed, revisioned finance data for Quick Ledger.
-- All client writes go through save_finance_data/clear_finance_data so a
-- complete AppData replacement and its revision update are atomic.

create table public.finance_sync_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  revision bigint not null default 0 check (revision >= 0),
  updated_at timestamptz not null default now()
);

create table public.accounts (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  name text not null,
  institution text not null default '',
  account_type text not null,
  currency text not null default 'TWD',
  opening_balance_minor bigint not null,
  is_active boolean not null default true,
  note text not null default '',
  created_at timestamptz not null,
  updated_at timestamptz not null,
  origin text not null default 'user' check (origin in ('user', 'demo')),
  primary key (user_id, id)
);

create table public.user_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  default_currency text not null default 'TWD',
  default_payment_method text not null default 'creditCard',
  default_category text not null default '餐飲',
  default_collection_account_id text,
  line_pay_qr_data text not null default '',
  bank_qr_data text not null default '',
  bank_account_info text not null default '',
  reminders_enabled boolean not null default true,
  line_reminders_enabled boolean not null default false,
  mask_balances boolean not null default false,
  foreign key (user_id, default_collection_account_id)
    references public.accounts(user_id, id)
    deferrable initially deferred
);

create table public.fx_rates (
  user_id uuid not null references auth.users(id) on delete cascade,
  from_currency text not null,
  to_currency text not null,
  rate_micros bigint not null check (rate_micros > 0),
  updated_at timestamptz not null,
  primary key (user_id, from_currency, to_currency)
);

create table public.balance_adjustments (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  account_id text not null,
  amount_minor bigint not null,
  adjustment_date timestamptz not null,
  reason text not null,
  origin text not null default 'user' check (origin in ('user', 'demo')),
  primary key (user_id, id),
  foreign key (user_id, account_id)
    references public.accounts(user_id, id)
    deferrable initially deferred
);

create table public.credit_cards (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  name text not null,
  bank text not null,
  last_four text not null,
  closing_day integer not null check (closing_day between 1 and 31),
  due_day integer not null check (due_day between 1 and 31),
  auto_debit_day integer not null check (auto_debit_day between 1 and 31),
  debit_account_id text not null,
  is_active boolean not null default true,
  note text not null default '',
  origin text not null default 'user' check (origin in ('user', 'demo')),
  primary key (user_id, id),
  foreign key (user_id, debit_account_id)
    references public.accounts(user_id, id)
    deferrable initially deferred
);

create table public.card_bills (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  card_id text not null,
  bill_month text not null,
  manual_adjustment_minor bigint not null default 0,
  paid_minor bigint not null default 0 check (paid_minor >= 0),
  due_date timestamptz not null,
  auto_debit_date timestamptz not null,
  note text not null default '',
  origin text not null default 'user' check (origin in ('user', 'demo')),
  primary key (user_id, id),
  foreign key (user_id, card_id)
    references public.credit_cards(user_id, id)
    deferrable initially deferred
);

create table public.expenses (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  expense_date timestamptz not null,
  amount_minor bigint not null check (amount_minor >= 0),
  payment_method text not null,
  item text not null,
  category text not null,
  account_id text,
  card_id text,
  bill_id text,
  merchant text not null default '',
  note text not null default '',
  is_necessary boolean not null default false,
  origin text not null default 'user' check (origin in ('user', 'demo')),
  primary key (user_id, id),
  foreign key (user_id, account_id)
    references public.accounts(user_id, id)
    deferrable initially deferred,
  foreign key (user_id, card_id)
    references public.credit_cards(user_id, id)
    deferrable initially deferred,
  foreign key (user_id, bill_id)
    references public.card_bills(user_id, id)
    deferrable initially deferred
);

create table public.investment_products (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  symbol text not null,
  name text not null,
  product_type text not null,
  currency text not null,
  current_price_minor bigint not null check (current_price_minor >= 0),
  price_updated_at timestamptz not null,
  note text not null default '',
  origin text not null default 'user' check (origin in ('user', 'demo')),
  primary key (user_id, id)
);

create table public.investment_transactions (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  transaction_date timestamptz not null,
  transaction_type text not null,
  product_id text not null,
  quantity_micros bigint not null check (quantity_micros >= 0),
  price_minor bigint not null check (price_minor >= 0),
  fee_minor bigint not null default 0 check (fee_minor >= 0),
  tax_minor bigint not null default 0 check (tax_minor >= 0),
  debit_account_id text,
  credit_account_id text,
  note text not null default '',
  origin text not null default 'user' check (origin in ('user', 'demo')),
  primary key (user_id, id),
  foreign key (user_id, product_id)
    references public.investment_products(user_id, id)
    deferrable initially deferred,
  foreign key (user_id, debit_account_id)
    references public.accounts(user_id, id)
    deferrable initially deferred,
  foreign key (user_id, credit_account_id)
    references public.accounts(user_id, id)
    deferrable initially deferred
);

create table public.investment_adjustments (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  product_id text not null,
  adjustment_date timestamptz not null,
  quantity_micros bigint not null check (quantity_micros >= 0),
  average_cost_minor bigint not null check (average_cost_minor >= 0),
  reason text not null,
  origin text not null default 'user' check (origin in ('user', 'demo')),
  primary key (user_id, id),
  foreign key (user_id, product_id)
    references public.investment_products(user_id, id)
    deferrable initially deferred
);

create table public.group_orders (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  name text not null,
  order_date timestamptz not null,
  platform text not null,
  card_id text not null,
  total_minor bigint not null check (total_minor >= 0),
  delivery_fee_minor bigint not null default 0 check (delivery_fee_minor >= 0),
  service_fee_minor bigint not null default 0 check (service_fee_minor >= 0),
  discount_minor bigint not null default 0 check (discount_minor >= 0),
  include_self_in_delivery_fee boolean not null default false,
  include_self_in_service_fee boolean not null default false,
  fee_rounding_policy text not null default 'exactRemainder',
  import_source text,
  import_warnings text[] not null default '{}',
  reconciliation_difference_minor bigint not null default 0,
  payment_last_four text,
  split_method text not null,
  note text not null default '',
  bill_id text,
  origin text not null default 'user' check (origin in ('user', 'demo')),
  primary key (user_id, id),
  foreign key (user_id, card_id)
    references public.credit_cards(user_id, id)
    deferrable initially deferred,
  foreign key (user_id, bill_id)
    references public.card_bills(user_id, id)
    deferrable initially deferred
);

create table public.order_participants (
  user_id uuid not null references auth.users(id) on delete cascade,
  order_id text not null,
  id text not null,
  name text not null,
  is_self boolean not null default false,
  item_name text not null,
  item_amount_minor bigint not null check (item_amount_minor >= 0),
  shared_fee_minor bigint not null default 0,
  discount_minor bigint not null default 0 check (discount_minor >= 0),
  discount_eligible boolean not null default false,
  discount_is_fixed boolean not null default false,
  suggested_due_minor bigint,
  final_due_minor bigint,
  collection_status text not null,
  collection_method text not null default '',
  collection_account_id text,
  collection_token text not null,
  collected_at timestamptz,
  note text not null default '',
  primary key (user_id, order_id, id),
  foreign key (user_id, order_id)
    references public.group_orders(user_id, id)
    on delete cascade
    deferrable initially deferred,
  foreign key (user_id, collection_account_id)
    references public.accounts(user_id, id)
    deferrable initially deferred
);

create table public.card_bill_expenses (
  user_id uuid not null references auth.users(id) on delete cascade,
  bill_id text not null,
  expense_id text not null,
  position integer not null check (position >= 0),
  primary key (user_id, bill_id, expense_id),
  foreign key (user_id, bill_id)
    references public.card_bills(user_id, id)
    on delete cascade
    deferrable initially deferred,
  foreign key (user_id, expense_id)
    references public.expenses(user_id, id)
    deferrable initially deferred
);

create table public.card_bill_orders (
  user_id uuid not null references auth.users(id) on delete cascade,
  bill_id text not null,
  order_id text not null,
  position integer not null check (position >= 0),
  primary key (user_id, bill_id, order_id),
  foreign key (user_id, bill_id)
    references public.card_bills(user_id, id)
    on delete cascade
    deferrable initially deferred,
  foreign key (user_id, order_id)
    references public.group_orders(user_id, id)
    deferrable initially deferred
);

create index balance_adjustments_user_date_idx
  on public.balance_adjustments(user_id, adjustment_date desc);
create index expenses_user_date_idx
  on public.expenses(user_id, expense_date desc);
create index investment_transactions_user_date_idx
  on public.investment_transactions(user_id, transaction_date desc);
create index group_orders_user_date_idx
  on public.group_orders(user_id, order_date desc);
create index order_participants_user_status_idx
  on public.order_participants(user_id, collection_status);

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'finance_sync_state', 'accounts', 'user_settings', 'fx_rates',
    'balance_adjustments', 'credit_cards', 'card_bills', 'expenses',
    'investment_products', 'investment_transactions',
    'investment_adjustments', 'group_orders', 'order_participants',
    'card_bill_expenses', 'card_bill_orders'
  ]
  loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format(
      'create policy %I on public.%I for all to authenticated ' ||
      'using (user_id = auth.uid()) with check (user_id = auth.uid())',
      table_name || '_owner_policy',
      table_name
    );
    execute format('revoke all on public.%I from anon, authenticated', table_name);
  end loop;
end
$$;

create or replace function public.load_finance_data()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := auth.uid();
  state public.finance_sync_state%rowtype;
  payload jsonb;
begin
  if uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into state
  from public.finance_sync_state
  where user_id = uid;

  if not found then
    return jsonb_build_object(
      'exists', false,
      'revision', 0,
      'updatedAt', null,
      'data', jsonb_build_object(
        'schemaVersion', 4,
        'settings', jsonb_build_object(),
        'accounts', '[]'::jsonb,
        'balanceAdjustments', '[]'::jsonb,
        'expenses', '[]'::jsonb,
        'cards', '[]'::jsonb,
        'bills', '[]'::jsonb,
        'products', '[]'::jsonb,
        'investmentTransactions', '[]'::jsonb,
        'investmentAdjustments', '[]'::jsonb,
        'orders', '[]'::jsonb
      )
    );
  end if;

  select jsonb_build_object(
    'schemaVersion', 4,
    'settings', coalesce((
      select jsonb_build_object(
        'defaultCurrency', s.default_currency,
        'defaultPaymentMethod', s.default_payment_method,
        'defaultCategory', s.default_category,
        'defaultCollectionAccountId', s.default_collection_account_id,
        'linePayQrData', s.line_pay_qr_data,
        'bankQrData', s.bank_qr_data,
        'bankAccountInfo', s.bank_account_info,
        'remindersEnabled', s.reminders_enabled,
        'lineRemindersEnabled', s.line_reminders_enabled,
        'maskBalances', s.mask_balances,
        'fxRates', coalesce((
          select jsonb_agg(jsonb_build_object(
            'from', f.from_currency,
            'to', f.to_currency,
            'rateMicros', f.rate_micros,
            'updatedAt', f.updated_at
          ) order by f.from_currency, f.to_currency)
          from public.fx_rates f where f.user_id = uid
        ), '[]'::jsonb)
      )
      from public.user_settings s where s.user_id = uid
    ), jsonb_build_object()),
    'accounts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', a.id, 'userId', a.user_id::text, 'name', a.name,
        'institution', a.institution, 'type', a.account_type,
        'currency', a.currency, 'openingBalanceMinor', a.opening_balance_minor,
        'isActive', a.is_active, 'note', a.note, 'createdAt', a.created_at,
        'updatedAt', a.updated_at, 'origin', a.origin
      ) order by a.created_at, a.id)
      from public.accounts a where a.user_id = uid
    ), '[]'::jsonb),
    'balanceAdjustments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', a.id, 'userId', a.user_id::text, 'accountId', a.account_id,
        'amountMinor', a.amount_minor, 'date', a.adjustment_date,
        'reason', a.reason, 'origin', a.origin
      ) order by a.adjustment_date, a.id)
      from public.balance_adjustments a where a.user_id = uid
    ), '[]'::jsonb),
    'expenses', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', e.id, 'userId', e.user_id::text, 'date', e.expense_date,
        'amountMinor', e.amount_minor, 'paymentMethod', e.payment_method,
        'item', e.item, 'category', e.category, 'accountId', e.account_id,
        'cardId', e.card_id, 'billId', e.bill_id, 'merchant', e.merchant,
        'note', e.note, 'isNecessary', e.is_necessary, 'origin', e.origin
      ) order by e.expense_date, e.id)
      from public.expenses e where e.user_id = uid
    ), '[]'::jsonb),
    'cards', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id, 'userId', c.user_id::text, 'name', c.name,
        'bank', c.bank, 'lastFour', c.last_four, 'closingDay', c.closing_day,
        'dueDay', c.due_day, 'autoDebitDay', c.auto_debit_day,
        'debitAccountId', c.debit_account_id, 'isActive', c.is_active,
        'note', c.note, 'origin', c.origin
      ) order by c.id)
      from public.credit_cards c where c.user_id = uid
    ), '[]'::jsonb),
    'bills', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', b.id, 'userId', b.user_id::text, 'cardId', b.card_id,
        'month', b.bill_month,
        'chargeIds', coalesce((
          select jsonb_agg(x.charge_id order by x.position, x.charge_id)
          from (
            select 'expense:' || be.expense_id as charge_id, be.position
            from public.card_bill_expenses be
            where be.user_id = uid and be.bill_id = b.id
            union all
            select 'order:' || bo.order_id, bo.position
            from public.card_bill_orders bo
            where bo.user_id = uid and bo.bill_id = b.id
          ) x
        ), '[]'::jsonb),
        'manualAdjustmentMinor', b.manual_adjustment_minor,
        'paidMinor', b.paid_minor, 'dueDate', b.due_date,
        'autoDebitDate', b.auto_debit_date, 'note', b.note, 'origin', b.origin
      ) order by b.bill_month, b.id)
      from public.card_bills b where b.user_id = uid
    ), '[]'::jsonb),
    'products', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'userId', p.user_id::text, 'symbol', p.symbol,
        'name', p.name, 'type', p.product_type, 'currency', p.currency,
        'currentPriceMinor', p.current_price_minor,
        'priceUpdatedAt', p.price_updated_at, 'note', p.note, 'origin', p.origin
      ) order by p.id)
      from public.investment_products p where p.user_id = uid
    ), '[]'::jsonb),
    'investmentTransactions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'userId', t.user_id::text, 'date', t.transaction_date,
        'type', t.transaction_type, 'productId', t.product_id,
        'quantityMicros', t.quantity_micros, 'priceMinor', t.price_minor,
        'feeMinor', t.fee_minor, 'taxMinor', t.tax_minor,
        'debitAccountId', t.debit_account_id,
        'creditAccountId', t.credit_account_id, 'note', t.note,
        'origin', t.origin
      ) order by t.transaction_date, t.id)
      from public.investment_transactions t where t.user_id = uid
    ), '[]'::jsonb),
    'investmentAdjustments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', a.id, 'userId', a.user_id::text, 'productId', a.product_id,
        'date', a.adjustment_date, 'quantityMicros', a.quantity_micros,
        'averageCostMinor', a.average_cost_minor, 'reason', a.reason,
        'origin', a.origin
      ) order by a.adjustment_date, a.id)
      from public.investment_adjustments a where a.user_id = uid
    ), '[]'::jsonb),
    'orders', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', o.id, 'userId', o.user_id::text, 'name', o.name,
        'date', o.order_date, 'platform', o.platform, 'cardId', o.card_id,
        'totalMinor', o.total_minor, 'deliveryFeeMinor', o.delivery_fee_minor,
        'serviceFeeMinor', o.service_fee_minor, 'discountMinor', o.discount_minor,
        'includeSelfInDeliveryFee', o.include_self_in_delivery_fee,
        'includeSelfInServiceFee', o.include_self_in_service_fee,
        'feeRoundingPolicy', o.fee_rounding_policy,
        'importSource', o.import_source, 'importWarnings', to_jsonb(o.import_warnings),
        'reconciliationDifferenceMinor', o.reconciliation_difference_minor,
        'paymentLastFour', o.payment_last_four, 'splitMethod', o.split_method,
        'note', o.note, 'billId', o.bill_id, 'origin', o.origin,
        'participants', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', p.id, 'name', p.name, 'isSelf', p.is_self,
            'itemName', p.item_name, 'itemAmountMinor', p.item_amount_minor,
            'sharedFeeMinor', p.shared_fee_minor,
            'discountMinor', p.discount_minor,
            'discountEligible', p.discount_eligible,
            'discountIsFixed', p.discount_is_fixed,
            'suggestedDueMinor', p.suggested_due_minor,
            'finalDueMinor', p.final_due_minor, 'status', p.collection_status,
            'collectionMethod', p.collection_method,
            'collectionAccountId', p.collection_account_id,
            'token', p.collection_token, 'collectedAt', p.collected_at,
            'note', p.note
          ) order by p.id)
          from public.order_participants p
          where p.user_id = uid and p.order_id = o.id
        ), '[]'::jsonb)
      ) order by o.order_date, o.id)
      from public.group_orders o where o.user_id = uid
    ), '[]'::jsonb)
  ) into payload;

  return jsonb_build_object(
    'exists', true,
    'revision', state.revision,
    'updatedAt', state.updated_at,
    'data', payload
  );
end
$$;

create or replace function public.save_finance_data(
  expected_revision bigint,
  data jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := auth.uid();
  current_revision bigint;
  next_revision bigint;
  item jsonb;
  nested jsonb;
  bill_item jsonb;
  charge text;
  charge_position integer;
begin
  if uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if jsonb_typeof(data) <> 'object' then
    raise exception 'invalid_finance_data';
  end if;
  if coalesce((data->>'schemaVersion')::integer, 0) <> 4 then
    raise exception 'unsupported_schema_version';
  end if;

  insert into public.finance_sync_state(user_id, revision)
  values (uid, 0)
  on conflict (user_id) do nothing;

  select revision into current_revision
  from public.finance_sync_state
  where user_id = uid
  for update;

  if expected_revision <> current_revision then
    return jsonb_build_object(
      'status', 'conflict',
      'revision', current_revision,
      'updatedAt', (
        select updated_at from public.finance_sync_state where user_id = uid
      )
    );
  end if;

  set constraints all deferred;

  delete from public.card_bill_expenses where user_id = uid;
  delete from public.card_bill_orders where user_id = uid;
  delete from public.order_participants where user_id = uid;
  delete from public.investment_transactions where user_id = uid;
  delete from public.investment_adjustments where user_id = uid;
  delete from public.balance_adjustments where user_id = uid;
  delete from public.expenses where user_id = uid;
  delete from public.group_orders where user_id = uid;
  delete from public.card_bills where user_id = uid;
  delete from public.credit_cards where user_id = uid;
  delete from public.user_settings where user_id = uid;
  delete from public.fx_rates where user_id = uid;
  delete from public.investment_products where user_id = uid;
  delete from public.accounts where user_id = uid;

  for item in select value from jsonb_array_elements(coalesce(data->'accounts', '[]'::jsonb))
  loop
    insert into public.accounts values (
      uid, item->>'id', item->>'name', coalesce(item->>'institution', ''),
      item->>'type', coalesce(item->>'currency', 'TWD'),
      (item->>'openingBalanceMinor')::bigint,
      coalesce((item->>'isActive')::boolean, true),
      coalesce(item->>'note', ''), (item->>'createdAt')::timestamptz,
      (item->>'updatedAt')::timestamptz, coalesce(item->>'origin', 'user')
    );
  end loop;

  item := coalesce(data->'settings', '{}'::jsonb);
  insert into public.user_settings values (
    uid, coalesce(item->>'defaultCurrency', 'TWD'),
    coalesce(item->>'defaultPaymentMethod', 'creditCard'),
    coalesce(item->>'defaultCategory', '餐飲'),
    nullif(item->>'defaultCollectionAccountId', ''),
    coalesce(item->>'linePayQrData', ''), coalesce(item->>'bankQrData', ''),
    coalesce(item->>'bankAccountInfo', ''),
    coalesce((item->>'remindersEnabled')::boolean, true),
    coalesce((item->>'lineRemindersEnabled')::boolean, false),
    coalesce((item->>'maskBalances')::boolean, false)
  );
  for nested in select value from jsonb_array_elements(coalesce(item->'fxRates', '[]'::jsonb))
  loop
    insert into public.fx_rates values (
      uid, nested->>'from', nested->>'to',
      (nested->>'rateMicros')::bigint, (nested->>'updatedAt')::timestamptz
    );
  end loop;

  for item in select value from jsonb_array_elements(coalesce(data->'balanceAdjustments', '[]'::jsonb))
  loop
    insert into public.balance_adjustments values (
      uid, item->>'id', item->>'accountId',
      (item->>'amountMinor')::bigint, (item->>'date')::timestamptz,
      item->>'reason', coalesce(item->>'origin', 'user')
    );
  end loop;

  for item in select value from jsonb_array_elements(coalesce(data->'cards', '[]'::jsonb))
  loop
    insert into public.credit_cards values (
      uid, item->>'id', item->>'name', item->>'bank', item->>'lastFour',
      (item->>'closingDay')::integer, (item->>'dueDay')::integer,
      (item->>'autoDebitDay')::integer, item->>'debitAccountId',
      coalesce((item->>'isActive')::boolean, true),
      coalesce(item->>'note', ''), coalesce(item->>'origin', 'user')
    );
  end loop;

  for item in select value from jsonb_array_elements(coalesce(data->'bills', '[]'::jsonb))
  loop
    insert into public.card_bills values (
      uid, item->>'id', item->>'cardId', item->>'month',
      coalesce((item->>'manualAdjustmentMinor')::bigint, 0),
      coalesce((item->>'paidMinor')::bigint, 0),
      (item->>'dueDate')::timestamptz,
      (item->>'autoDebitDate')::timestamptz,
      coalesce(item->>'note', ''), coalesce(item->>'origin', 'user')
    );
  end loop;

  for item in select value from jsonb_array_elements(coalesce(data->'expenses', '[]'::jsonb))
  loop
    insert into public.expenses values (
      uid, item->>'id', (item->>'date')::timestamptz,
      (item->>'amountMinor')::bigint, item->>'paymentMethod',
      item->>'item', item->>'category', nullif(item->>'accountId', ''),
      nullif(item->>'cardId', ''), nullif(item->>'billId', ''),
      coalesce(item->>'merchant', ''), coalesce(item->>'note', ''),
      coalesce((item->>'isNecessary')::boolean, false),
      coalesce(item->>'origin', 'user')
    );
  end loop;

  for item in select value from jsonb_array_elements(coalesce(data->'products', '[]'::jsonb))
  loop
    insert into public.investment_products values (
      uid, item->>'id', item->>'symbol', item->>'name', item->>'type',
      item->>'currency', (item->>'currentPriceMinor')::bigint,
      (item->>'priceUpdatedAt')::timestamptz,
      coalesce(item->>'note', ''), coalesce(item->>'origin', 'user')
    );
  end loop;

  for item in select value from jsonb_array_elements(coalesce(data->'investmentTransactions', '[]'::jsonb))
  loop
    insert into public.investment_transactions values (
      uid, item->>'id', (item->>'date')::timestamptz, item->>'type',
      item->>'productId', (item->>'quantityMicros')::bigint,
      (item->>'priceMinor')::bigint, coalesce((item->>'feeMinor')::bigint, 0),
      coalesce((item->>'taxMinor')::bigint, 0),
      nullif(item->>'debitAccountId', ''),
      nullif(item->>'creditAccountId', ''),
      coalesce(item->>'note', ''), coalesce(item->>'origin', 'user')
    );
  end loop;

  for item in select value from jsonb_array_elements(coalesce(data->'investmentAdjustments', '[]'::jsonb))
  loop
    insert into public.investment_adjustments values (
      uid, item->>'id', item->>'productId', (item->>'date')::timestamptz,
      (item->>'quantityMicros')::bigint,
      (item->>'averageCostMinor')::bigint, item->>'reason',
      coalesce(item->>'origin', 'user')
    );
  end loop;

  for item in select value from jsonb_array_elements(coalesce(data->'orders', '[]'::jsonb))
  loop
    insert into public.group_orders values (
      uid, item->>'id', item->>'name', (item->>'date')::timestamptz,
      item->>'platform', item->>'cardId', (item->>'totalMinor')::bigint,
      coalesce((item->>'deliveryFeeMinor')::bigint, 0),
      coalesce((item->>'serviceFeeMinor')::bigint, 0),
      coalesce((item->>'discountMinor')::bigint, 0),
      coalesce((item->>'includeSelfInDeliveryFee')::boolean, false),
      coalesce((item->>'includeSelfInServiceFee')::boolean, false),
      coalesce(item->>'feeRoundingPolicy', 'exactRemainder'),
      nullif(item->>'importSource', ''),
      array(select jsonb_array_elements_text(coalesce(item->'importWarnings', '[]'::jsonb))),
      coalesce((item->>'reconciliationDifferenceMinor')::bigint, 0),
      nullif(item->>'paymentLastFour', ''), item->>'splitMethod',
      coalesce(item->>'note', ''), nullif(item->>'billId', ''),
      coalesce(item->>'origin', 'user')
    );
    for nested in select value from jsonb_array_elements(coalesce(item->'participants', '[]'::jsonb))
    loop
      insert into public.order_participants values (
        uid, item->>'id', nested->>'id', nested->>'name',
        coalesce((nested->>'isSelf')::boolean, false), nested->>'itemName',
        (nested->>'itemAmountMinor')::bigint,
        coalesce((nested->>'sharedFeeMinor')::bigint, 0),
        coalesce((nested->>'discountMinor')::bigint, 0),
        coalesce((nested->>'discountEligible')::boolean, false),
        coalesce((nested->>'discountIsFixed')::boolean, false),
        (nested->>'suggestedDueMinor')::bigint,
        (nested->>'finalDueMinor')::bigint, nested->>'status',
        coalesce(nested->>'collectionMethod', ''),
        nullif(nested->>'collectionAccountId', ''),
        nested->>'token', (nested->>'collectedAt')::timestamptz,
        coalesce(nested->>'note', '')
      );
    end loop;
  end loop;

  for bill_item in select value from jsonb_array_elements(coalesce(data->'bills', '[]'::jsonb))
  loop
    charge_position := 0;
    for charge in select value #>> '{}' from jsonb_array_elements(coalesce(bill_item->'chargeIds', '[]'::jsonb))
    loop
      if charge like 'expense:%' then
        insert into public.card_bill_expenses values (
          uid, bill_item->>'id', substr(charge, 9), charge_position
        );
      elsif charge like 'order:%' then
        insert into public.card_bill_orders values (
          uid, bill_item->>'id', substr(charge, 7), charge_position
        );
      else
        raise exception 'invalid_charge_id: %', charge;
      end if;
      charge_position := charge_position + 1;
    end loop;
  end loop;

  next_revision := current_revision + 1;
  update public.finance_sync_state
  set revision = next_revision, updated_at = now()
  where user_id = uid;

  return jsonb_build_object(
    'status', 'saved',
    'revision', next_revision,
    'updatedAt', (
      select updated_at from public.finance_sync_state where user_id = uid
    )
  );
end
$$;

create or replace function public.clear_finance_data(expected_revision bigint)
returns jsonb
language sql
security definer
set search_path = public, pg_temp
as $$
  select public.save_finance_data(
    expected_revision,
    jsonb_build_object(
      'schemaVersion', 4,
      'settings', jsonb_build_object(),
      'accounts', '[]'::jsonb,
      'balanceAdjustments', '[]'::jsonb,
      'expenses', '[]'::jsonb,
      'cards', '[]'::jsonb,
      'bills', '[]'::jsonb,
      'products', '[]'::jsonb,
      'investmentTransactions', '[]'::jsonb,
      'investmentAdjustments', '[]'::jsonb,
      'orders', '[]'::jsonb
    )
  );
$$;

revoke all on function public.load_finance_data() from public;
revoke all on function public.save_finance_data(bigint, jsonb) from public;
revoke all on function public.clear_finance_data(bigint) from public;
grant execute on function public.load_finance_data() to authenticated;
grant execute on function public.save_finance_data(bigint, jsonb) to authenticated;
grant execute on function public.clear_finance_data(bigint) to authenticated;
