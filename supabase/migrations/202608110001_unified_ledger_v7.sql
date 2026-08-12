-- User-maintained categories and the schema v7 unified ledger.
-- Legacy finance tables remain authoritative during the compatibility window.

create table public.financial_account_metadata (
  user_id uuid not null references auth.users(id) on delete cascade,
  account_id text not null,
  account_kind text not null default 'asset'
    check (account_kind in ('asset', 'liability', 'receivable')),
  account_subtype text not null default 'bank',
  primary key (user_id, account_id),
  foreign key (user_id, account_id) references public.accounts(user_id, id)
    on delete cascade deferrable initially deferred
);

create table public.credit_card_profiles_v7 (
  user_id uuid not null references auth.users(id) on delete cascade,
  card_id text not null,
  liability_account_id text not null,
  primary key (user_id, card_id),
  foreign key (user_id, card_id) references public.credit_cards(user_id, id)
    on delete cascade deferrable initially deferred,
  foreign key (user_id, liability_account_id)
    references public.accounts(user_id, id)
    deferrable initially deferred
);

create table public.bookkeeping_categories (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  name text not null check (char_length(trim(name)) between 1 and 20),
  category_kind text not null check (category_kind in ('expense', 'income')),
  icon_key text not null,
  color_key text not null,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  is_built_in boolean not null default false,
  merged_into_category_id text,
  primary key (user_id, id),
  unique (user_id, category_kind, name),
  foreign key (user_id, merged_into_category_id)
    references public.bookkeeping_categories(user_id, id)
    deferrable initially deferred
);

create table public.user_settings_v7 (
  user_id uuid primary key references auth.users(id) on delete cascade,
  default_expense_category_id text not null,
  foreign key (user_id, default_expense_category_id)
    references public.bookkeeping_categories(user_id, id)
    deferrable initially deferred
);

create table public.financial_transactions (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  transaction_date timestamptz not null,
  transaction_type text not null,
  label text not null,
  amount_minor bigint not null check (amount_minor >= 0),
  currency text not null default 'TWD',
  category_id text,
  note text not null default '',
  related_entity_type text,
  related_entity_id text,
  origin text not null default 'user' check (origin in ('user', 'demo')),
  primary key (user_id, id),
  foreign key (user_id, category_id)
    references public.bookkeeping_categories(user_id, id)
    deferrable initially deferred
);

create table public.account_impacts (
  user_id uuid not null references auth.users(id) on delete cascade,
  transaction_id text not null,
  position integer not null check (position >= 0),
  account_id text not null,
  amount_minor bigint not null,
  currency text not null default 'TWD',
  primary key (user_id, transaction_id, position),
  foreign key (user_id, transaction_id)
    references public.financial_transactions(user_id, id)
    on delete cascade deferrable initially deferred,
  foreign key (user_id, account_id)
    references public.accounts(user_id, id)
    deferrable initially deferred
);

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'financial_account_metadata', 'credit_card_profiles_v7',
    'bookkeeping_categories', 'user_settings_v7',
    'financial_transactions', 'account_impacts'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format(
      'create policy %I on public.%I for all using (auth.uid() = user_id) with check (auth.uid() = user_id)',
      table_name || '_owner_policy', table_name
    );
    execute format('revoke all on public.%I from anon, authenticated', table_name);
  end loop;
end
$$;

create or replace function public.sync_expense_to_v7()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  category_id text;
  liability_id text;
begin
  if tg_op = 'DELETE' then
    delete from public.financial_transactions
      where user_id = old.user_id and id = 'expense:' || old.id;
    return old;
  end if;
  if not exists (
    select 1 from public.bookkeeping_categories c where c.user_id = new.user_id
  ) then
    return new;
  end if;

  select c.id into category_id from public.bookkeeping_categories c
  where c.user_id = new.user_id and c.category_kind = 'expense'
    and lower(trim(c.name)) = lower(trim(new.category))
  order by c.is_active desc, c.sort_order limit 1;
  if category_id is null then
    select coalesce(s.default_expense_category_id, 'expense-other')
      into category_id from public.user_settings_v7 s
      where s.user_id = new.user_id;
  end if;

  insert into public.financial_transactions(
    user_id, id, transaction_date, transaction_type, label, amount_minor,
    currency, category_id, note, related_entity_type, related_entity_id, origin
  ) values (
    new.user_id, 'expense:' || new.id, new.expense_date, 'expense', new.item,
    new.amount_minor, 'TWD', category_id, new.note, 'expense', new.id, new.origin
  ) on conflict (user_id, id) do update set
    transaction_date = excluded.transaction_date,
    label = excluded.label, amount_minor = excluded.amount_minor,
    category_id = excluded.category_id, note = excluded.note;

  delete from public.account_impacts
    where user_id = new.user_id and transaction_id = 'expense:' || new.id;
  if new.payment_method = 'creditCard' and new.card_id is not null then
    select c.liability_account_id into liability_id
      from public.credit_card_profiles_v7 c
      where c.user_id = new.user_id and c.card_id = new.card_id;
    if liability_id is not null then
      insert into public.account_impacts values (
        new.user_id, 'expense:' || new.id, 0, liability_id,
        new.amount_minor, 'TWD'
      );
    end if;
  elsif new.payment_method <> 'telecomBill' and new.account_id is not null then
    insert into public.account_impacts values (
      new.user_id, 'expense:' || new.id, 0, new.account_id,
      -new.amount_minor, coalesce((select a.currency from public.accounts a
        where a.user_id = new.user_id and a.id = new.account_id), 'TWD')
    );
  end if;
  return new;
end
$$;

drop trigger if exists expenses_sync_v7 on public.expenses;
create trigger expenses_sync_v7
after insert or update or delete on public.expenses
for each row execute function public.sync_expense_to_v7();

create or replace function public.line_list_bookkeeping_categories(
  p_line_user_id text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := public.line_linked_owner_id(p_line_user_id);
  items jsonb;
begin
  if uid is null then return jsonb_build_object('status', 'not_linked'); end if;
  select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name)
    order by c.sort_order, c.name) into items
  from public.bookkeeping_categories c
  where c.user_id = uid and c.category_kind = 'expense' and c.is_active;
  if items is null then
    items := jsonb_build_array(
      jsonb_build_object('id', 'legacy-food', 'name', '餐飲'),
      jsonb_build_object('id', 'legacy-transport', 'name', '交通'),
      jsonb_build_object('id', 'legacy-shopping', 'name', '購物'),
      jsonb_build_object('id', 'legacy-entertainment', 'name', '娛樂'),
      jsonb_build_object('id', 'legacy-medical', 'name', '醫療'),
      jsonb_build_object('id', 'legacy-other', 'name', '其他')
    );
  end if;
  return jsonb_build_object('status', 'ok', 'items', items);
end
$$;

alter function public.load_finance_data() rename to load_finance_data_v6;
alter function public.save_finance_data(bigint, jsonb)
  rename to save_finance_data_v6;

create or replace function public.load_finance_data()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := auth.uid();
  response jsonb;
  payload jsonb;
begin
  if uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  response := public.load_finance_data_v6();
  if not exists (
    select 1 from public.bookkeeping_categories c where c.user_id = uid
  ) then
    return response;
  end if;

  payload := jsonb_set(
    coalesce(response->'data', '{}'::jsonb),
    '{schemaVersion}', '7'::jsonb, true
  );
  payload := jsonb_set(payload, '{categories}', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', c.id, 'userId', c.user_id::text, 'name', c.name,
      'kind', c.category_kind, 'iconKey', c.icon_key,
      'colorKey', c.color_key, 'sortOrder', c.sort_order,
      'isActive', c.is_active, 'isBuiltIn', c.is_built_in,
      'mergedIntoCategoryId', c.merged_into_category_id
    ) order by c.category_kind, c.sort_order, c.name)
    from public.bookkeeping_categories c where c.user_id = uid
  ), '[]'::jsonb), true);

  payload := jsonb_set(payload, '{transactions}', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', t.id, 'userId', t.user_id::text,
      'date', t.transaction_date, 'type', t.transaction_type,
      'label', t.label, 'amountMinor', t.amount_minor,
      'currency', t.currency, 'categoryId', t.category_id,
      'note', t.note, 'relatedEntityType', t.related_entity_type,
      'relatedEntityId', t.related_entity_id, 'origin', t.origin,
      'impacts', coalesce((select jsonb_agg(jsonb_build_object(
        'accountId', i.account_id, 'amountMinor', i.amount_minor,
        'currency', i.currency
      ) order by i.position) from public.account_impacts i
        where i.user_id = uid and i.transaction_id = t.id), '[]'::jsonb)
    ) order by t.transaction_date, t.id)
    from public.financial_transactions t where t.user_id = uid
  ), '[]'::jsonb), true);

  payload := jsonb_set(payload, '{accounts}', coalesce((
    select jsonb_agg(item || jsonb_build_object(
      'kind', coalesce(m.account_kind, 'asset'),
      'subtype', coalesce(m.account_subtype, 'bank')
    ) order by item->>'createdAt', item->>'id')
    from jsonb_array_elements(coalesce(payload->'accounts', '[]'::jsonb)) item
    join public.accounts a on a.user_id = uid and a.id = item->>'id'
    left join public.financial_account_metadata m
      on m.user_id = a.user_id and m.account_id = a.id
  ), '[]'::jsonb), true);

  payload := jsonb_set(payload, '{cards}', coalesce((
    select jsonb_agg(item || jsonb_build_object(
      'liabilityAccountId', p.liability_account_id
    ) order by item->>'name', item->>'id')
    from jsonb_array_elements(coalesce(payload->'cards', '[]'::jsonb)) item
    join public.credit_cards c on c.user_id = uid and c.id = item->>'id'
    left join public.credit_card_profiles_v7 p
      on p.user_id = c.user_id and p.card_id = c.id
  ), '[]'::jsonb), true);

  payload := jsonb_set(payload, '{settings}',
    coalesce(payload->'settings', '{}'::jsonb) || jsonb_build_object(
      'defaultExpenseCategoryId', coalesce((select s.default_expense_category_id
        from public.user_settings_v7 s where s.user_id = uid), 'expense-food')
    ), true);
  return jsonb_set(response, '{data}', payload, true);
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
  version integer;
  result jsonb;
  legacy_data jsonb;
  item jsonb;
  impact jsonb;
  impact_position integer;
begin
  if uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if jsonb_typeof(data) <> 'object' then
    raise exception 'invalid_finance_data';
  end if;
  version := coalesce((data->>'schemaVersion')::integer, 0);

  if version = 6 then
    if exists (
      select 1 from public.bookkeeping_categories c where c.user_id = uid
    ) then
      raise exception 'unsupported_schema_version_update_required';
    end if;
    return public.save_finance_data_v6(expected_revision, data);
  end if;
  if version <> 7 then
    raise exception 'unsupported_schema_version_update_required';
  end if;

  legacy_data := (data - 'categories' - 'transactions') ||
    jsonb_build_object('schemaVersion', 6);
  result := public.save_finance_data_v6(expected_revision, legacy_data);
  if result->>'status' = 'conflict' then return result; end if;

  delete from public.account_impacts where user_id = uid;
  delete from public.financial_transactions where user_id = uid;
  delete from public.user_settings_v7 where user_id = uid;
  delete from public.bookkeeping_categories where user_id = uid;

  for item in select value from jsonb_array_elements(
    coalesce(data->'categories', '[]'::jsonb)
  ) loop
    insert into public.bookkeeping_categories values (
      uid, item->>'id', trim(item->>'name'), item->>'kind',
      item->>'iconKey', item->>'colorKey',
      coalesce((item->>'sortOrder')::integer, 0),
      coalesce((item->>'isActive')::boolean, true),
      coalesce((item->>'isBuiltIn')::boolean, false),
      nullif(item->>'mergedIntoCategoryId', '')
    );
  end loop;

  for item in select value from jsonb_array_elements(
    coalesce(data->'transactions', '[]'::jsonb)
  ) loop
    insert into public.financial_transactions values (
      uid, item->>'id', (item->>'date')::timestamptz,
      item->>'type', item->>'label', (item->>'amountMinor')::bigint,
      coalesce(item->>'currency', 'TWD'), nullif(item->>'categoryId', ''),
      coalesce(item->>'note', ''), nullif(item->>'relatedEntityType', ''),
      nullif(item->>'relatedEntityId', ''), coalesce(item->>'origin', 'user')
    );
    impact_position := 0;
    for impact in select value from jsonb_array_elements(
      coalesce(item->'impacts', '[]'::jsonb)
    ) loop
      insert into public.account_impacts values (
        uid, item->>'id', impact_position, impact->>'accountId',
        (impact->>'amountMinor')::bigint,
        coalesce(impact->>'currency', 'TWD')
      );
      impact_position := impact_position + 1;
    end loop;
  end loop;

  for item in select value from jsonb_array_elements(
    coalesce(data->'accounts', '[]'::jsonb)
  ) loop
    insert into public.financial_account_metadata values (
      uid, item->>'id', coalesce(item->>'kind', 'asset'),
      coalesce(item->>'subtype', 'bank')
    ) on conflict (user_id, account_id) do update set
      account_kind = excluded.account_kind,
      account_subtype = excluded.account_subtype;
  end loop;

  for item in select value from jsonb_array_elements(
    coalesce(data->'cards', '[]'::jsonb)
  ) loop
    if nullif(item->>'liabilityAccountId', '') is not null then
      insert into public.credit_card_profiles_v7 values (
        uid, item->>'id', item->>'liabilityAccountId'
      ) on conflict (user_id, card_id) do update set
        liability_account_id = excluded.liability_account_id;
    end if;
  end loop;

  if nullif(data#>>'{settings,defaultExpenseCategoryId}', '') is not null then
    insert into public.user_settings_v7 values (
      uid, data#>>'{settings,defaultExpenseCategoryId}'
    ) on conflict (user_id) do update set
      default_expense_category_id = excluded.default_expense_category_id;
  end if;
  return result;
end
$$;

create or replace function public.clear_finance_data(expected_revision bigint)
returns jsonb
language sql
security definer
set search_path = public, pg_temp
as $$
  select public.save_finance_data(expected_revision, jsonb_build_object(
    'schemaVersion', 7, 'settings', '{}'::jsonb,
    'categories', '[]'::jsonb, 'transactions', '[]'::jsonb,
    'accounts', '[]'::jsonb, 'balanceAdjustments', '[]'::jsonb,
    'expenses', '[]'::jsonb, 'recurringExpenses', '[]'::jsonb,
    'recurringExpenseOccurrences', '[]'::jsonb,
    'telecomBillPayments', '[]'::jsonb, 'incomes', '[]'::jsonb,
    'cards', '[]'::jsonb, 'bills', '[]'::jsonb,
    'products', '[]'::jsonb, 'investmentTransactions', '[]'::jsonb,
    'investmentAdjustments', '[]'::jsonb,
    'investmentPriceHistory', '[]'::jsonb, 'orders', '[]'::jsonb
  ));
$$;

revoke all on function public.load_finance_data_v6() from public, anon, authenticated;
revoke all on function public.save_finance_data_v6(bigint, jsonb)
  from public, anon, authenticated;
revoke all on function public.load_finance_data() from public;
revoke all on function public.save_finance_data(bigint, jsonb) from public;
revoke all on function public.clear_finance_data(bigint) from public;
grant execute on function public.load_finance_data() to authenticated;
grant execute on function public.save_finance_data(bigint, jsonb) to authenticated;
grant execute on function public.clear_finance_data(bigint) to authenticated;
revoke all on function public.line_list_bookkeeping_categories(text) from public;
grant execute on function public.line_list_bookkeeping_categories(text)
  to service_role;
