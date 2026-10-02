-- 對帳 (reconciliation) of 電信帳單, on top of reconciliation_records_v11.
--
-- A telecomBill record checks one telecom_bill_payments row against the
-- carrier's real bill; target_id is the payment id and adjustment_id the
-- balance_adjustments row booked on the payment's debit account. The
-- load/save RPCs already pass targetType through verbatim, so only the
-- check constraint needs widening.

alter table public.reconciliation_records_v11
  drop constraint reconciliation_records_v11_target_type_check;
alter table public.reconciliation_records_v11
  add constraint reconciliation_records_v11_target_type_check
  check (target_type in ('account', 'cardBill', 'telecomBill'));
