-- LINE "已繳費" reply for credit-card bill reminders.
--
-- Before this, the only LINE reply on a bill reminder was "確認，這筆帳單不用
-- 再提醒" (line_acknowledge_bill_reminder), which just sets
-- reminder_dismissed. It never recorded a payment, so the bill kept an
-- outstanding balance and the overdue / auto-debit-failed alerts (which
-- reminder_dismissed deliberately doesn't suppress) kept firing, both in the
-- app and over LINE, even after the user had replied that they'd paid.
--
-- line_mark_card_bill_paid records the remaining balance as a real card
-- payment, exactly like CardsManager.recordBillPayment does on the client:
-- a cardPayment financial_transaction (debit account -, card liability -),
-- card_bills.paid_minor / paid_at updated, and the finance revision bumped
-- so an open app reloads instead of overwriting it with a stale save.

create or replace function public.line_mark_card_bill_paid(
  p_line_user_id text,
  p_bill_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := public.line_linked_owner_id(p_line_user_id);
  bill public.card_bills%rowtype;
  card public.credit_cards%rowtype;
  liability_id text;
  debit_currency text;
  statement_minor bigint;
  payment_count integer;
  paid_minor bigint;
  outstanding_minor bigint;
  paid_time timestamptz := now();
  transaction_id text;
  current_revision bigint;
  next_revision bigint;
begin
  if uid is null then
    return jsonb_build_object('status', 'not_linked');
  end if;

  -- Serialize with save_finance_data and other LINE writes first.
  insert into public.finance_sync_state(user_id, revision)
  values (uid, 0) on conflict (user_id) do nothing;
  select revision into current_revision
  from public.finance_sync_state where user_id = uid for update;

  select * into bill from public.card_bills
  where user_id = uid and id = p_bill_id for update;
  if not found then
    return jsonb_build_object('status', 'not_found');
  end if;
  select * into card from public.credit_cards
  where user_id = uid and id = bill.card_id;

  statement_minor := coalesce(
    (select rec.statement_amount_minor from public.card_bill_reconciliation_v9 rec
     where rec.user_id = uid and rec.bill_id = bill.id),
    public.card_bill_calculated_amount_minor(uid, bill.id)
  );
  -- Same rule as LedgerQueries.paidBillMinor: once any payment transaction
  -- exists, their sum is authoritative; otherwise fall back to paid_minor.
  select count(*), coalesce(sum(t.amount_minor), 0)
  into payment_count, paid_minor
  from public.financial_transactions t
  where t.user_id = uid and t.transaction_type = 'cardPayment'
    and t.related_entity_type = 'cardBill' and t.related_entity_id = bill.id;
  if payment_count = 0 then
    if bill.paid_minor > 0 then
      -- Legacy bill paid without transactions: adding one now would make
      -- the client's transaction sum smaller than what's already paid.
      return jsonb_build_object(
        'status', 'needs_app', 'cardName', card.name,
        'billMonth', bill.bill_month
      );
    end if;
    paid_minor := 0;
  end if;
  outstanding_minor := greatest(0, statement_minor - paid_minor);
  if outstanding_minor = 0 then
    return jsonb_build_object(
      'status', 'already_paid', 'cardName', card.name,
      'billMonth', bill.bill_month
    );
  end if;

  select p.liability_account_id into liability_id
  from public.credit_card_profiles_v7 p
  where p.user_id = uid and p.card_id = card.id;
  select a.currency into debit_currency
  from public.accounts a
  left join public.financial_account_metadata m
    on m.user_id = a.user_id and m.account_id = a.id
  where a.user_id = uid and a.id = card.debit_account_id
    and coalesce(m.account_kind, 'asset') = 'asset';
  if liability_id is null or debit_currency is null then
    return jsonb_build_object(
      'status', 'needs_app', 'cardName', card.name,
      'billMonth', bill.bill_month
    );
  end if;

  transaction_id := 'card-payment:' || bill.id || ':line-' ||
    (extract(epoch from paid_time) * 1000)::bigint;
  insert into public.financial_transactions(
    user_id, id, transaction_date, transaction_type, label, amount_minor,
    currency, category_id, note, related_entity_type, related_entity_id, origin
  ) values (
    uid, transaction_id, paid_time, 'cardPayment',
    card.name || ' ' || bill.bill_month || ' 帳單繳款', outstanding_minor,
    debit_currency, null, 'LINE 回覆已繳費', 'cardBill', bill.id, bill.origin
  );
  insert into public.account_impacts values
    (uid, transaction_id, 0, card.debit_account_id, -outstanding_minor, debit_currency),
    (uid, transaction_id, 1, liability_id, -outstanding_minor, 'TWD');

  update public.card_bills set paid_minor = statement_minor
  where user_id = uid and id = bill.id;
  insert into public.card_bill_report_metadata(user_id, bill_id, paid_at)
  values (uid, bill.id, paid_time)
  on conflict (user_id, bill_id) do update set paid_at = excluded.paid_at;

  next_revision := current_revision + 1;
  update public.finance_sync_state
  set revision = next_revision, updated_at = now() where user_id = uid;
  return jsonb_build_object(
    'status', 'saved', 'cardName', card.name, 'billMonth', bill.bill_month,
    'amountMinor', outstanding_minor, 'revision', next_revision
  );
end
$$;

-- Bills with a balance still owed, for when the user types "已繳費" instead
-- of tapping the reminder's quick reply; the webhook answers with one
-- "已繳費" button per bill.
create or replace function public.line_list_unpaid_card_bills(
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
begin
  if uid is null then
    return jsonb_build_object('status', 'not_linked');
  end if;
  return jsonb_build_object('status', 'ok', 'items', coalesce((
    select jsonb_agg(jsonb_build_object(
      'billId', item.id, 'cardName', item.card_name,
      'billMonth', item.bill_month, 'outstandingMinor', item.outstanding_minor
    ) order by item.due_date, item.id)
    from (
      select b.id, c.name as card_name, b.bill_month, b.due_date,
        greatest(0, coalesce(
          rec.statement_amount_minor,
          public.card_bill_calculated_amount_minor(uid, b.id)
        ) - b.paid_minor) as outstanding_minor
      from public.card_bills b
      join public.credit_cards c on c.user_id = b.user_id and c.id = b.card_id
      left join public.card_bill_reconciliation_v9 rec
        on rec.user_id = b.user_id and rec.bill_id = b.id
      where b.user_id = uid
    ) item
    where item.outstanding_minor > 0
  ), '[]'::jsonb));
end
$$;

-- The "don't remind me again" reply wrote card_bill_reminder_state without
-- bumping the revision, so the next save from an already-open app (whose
-- data still had reminderDismissed = false) passed the revision check and
-- save_finance_data's delete-and-reinsert silently undid the dismissal.
create or replace function public.line_acknowledge_bill_reminder(
  p_line_user_id text,
  p_bill_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := public.line_linked_owner_id(p_line_user_id);
  card_name text;
  bill_month text;
begin
  if uid is null then
    return jsonb_build_object('status', 'not_linked');
  end if;
  select c.name, b.bill_month into card_name, bill_month
  from public.card_bills b
  join public.credit_cards c on c.user_id = b.user_id and c.id = b.card_id
  where b.user_id = uid and b.id = p_bill_id;
  if card_name is null then
    return jsonb_build_object('status', 'not_found');
  end if;
  insert into public.card_bill_reminder_state(user_id, bill_id, reminder_dismissed)
  values (uid, p_bill_id, true)
  on conflict (user_id, bill_id) do update set reminder_dismissed = true;
  insert into public.finance_sync_state(user_id, revision)
  values (uid, 1)
  on conflict (user_id) do update
    set revision = public.finance_sync_state.revision + 1, updated_at = now();
  return jsonb_build_object(
    'status', 'saved', 'cardName', card_name, 'billMonth', bill_month
  );
end
$$;

revoke all on function public.line_mark_card_bill_paid(text, text) from public;
grant execute on function public.line_mark_card_bill_paid(text, text) to service_role;
revoke all on function public.line_list_unpaid_card_bills(text) from public;
grant execute on function public.line_list_unpaid_card_bills(text) to service_role;
revoke all on function public.line_acknowledge_bill_reminder(text, text) from public;
grant execute on function public.line_acknowledge_bill_reminder(text, text) to service_role;
