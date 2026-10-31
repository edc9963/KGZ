-- 投資 is no longer spending: the app leaves expenses filed under it out of
-- 本月支出 (see isSpendingCategory), so the LINE bot's summary does the same.
-- The money still left the account, so accountBalanceMinor keeps counting it.

alter function public.line_finance_summary(text) rename to line_finance_summary_v13;
create or replace function public.line_finance_summary(p_line_user_id text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := public.line_linked_owner_id(p_line_user_id);
  result jsonb;
  invested bigint;
begin
  result := public.line_finance_summary_v13(p_line_user_id);
  if uid is null or result->>'status' <> 'ok' then return result; end if;
  select coalesce(sum(e.amount_minor), 0) into invested
    from public.expenses e
    where e.user_id = uid
      and e.category = '投資'
      and date_trunc('month', e.expense_date at time zone 'Asia/Taipei')
          = date_trunc('month', now() at time zone 'Asia/Taipei');
  return jsonb_set(
    result,
    '{monthExpenseMinor}',
    to_jsonb(coalesce((result->>'monthExpenseMinor')::bigint, 0) - invested),
    true
  );
end
$$;

revoke all on function public.line_finance_summary_v13(text) from public, anon, authenticated, service_role;
revoke all on function public.line_finance_summary(text) from public, anon, authenticated;
grant execute on function public.line_finance_summary(text) to service_role;
