-- Re-label existing card_bills.bill_month from "the month the cycle's
-- closing date falls in" to "the month the cycle actually starts in" (the
-- day right after the *previous* closing date). The client now names bills
-- this way (see CardsManager._ensureBillsForCard /
-- LedgerQueries.cardBillLabelFor), since it matches how people talk about
-- "this month's card bill" (most of the cycle's charges land in that
-- month) rather than the month the statement happens to close in.
--
-- Example: a card that closes on the 1st has a cycle running Aug 2 - Sep 1.
-- It used to be filed as the "2026-09" bill (closing-month naming); it is
-- now the "2026-08" bill (start-month naming).
--
-- This migration only rewrites the bill_month text label. It does not
-- touch due_date, auto_debit_date, or which expenses/orders belong to
-- which bill (card_bill_expenses / card_bill_orders), so no charge ever
-- moves between bills - only the display month changes.
--
-- For most cards this shifts every existing bill's label back by one
-- month. It leaves a bill's label unchanged only when the card's closing
-- day gets clamped to the last day of the (shorter) label month - e.g.
-- closing day 29-31 landing on a 28-day February - because then the cycle
-- both starts and is keyed by that same calendar month already.

do $$
declare
  rec record;
  month_start date;
  prev_month_start date;
  prev_month_last_day int;
  previous_closing date;
  new_month text;
  updated_count int := 0;
begin
  for rec in
    select b.user_id, b.id, b.card_id, b.bill_month, c.closing_day
    from public.card_bills b
    join public.credit_cards c
      on c.user_id = b.user_id and c.id = b.card_id
    where b.bill_month ~ '^\d{4}-\d{2}$'
    order by b.user_id, b.card_id, b.bill_month
  loop
    month_start := to_date(rec.bill_month || '-01', 'YYYY-MM-DD');
    prev_month_start := (month_start - interval '1 month')::date;
    prev_month_last_day := extract(day from (month_start - 1))::int;
    previous_closing :=
      prev_month_start + (least(rec.closing_day, prev_month_last_day) - 1);
    new_month := to_char(previous_closing + 1, 'YYYY-MM');

    continue when new_month = rec.bill_month;

    if exists (
      select 1 from public.card_bills other
      where other.user_id = rec.user_id
        and other.card_id = rec.card_id
        and other.id <> rec.id
        and other.bill_month = new_month
    ) then
      raise exception
        'card_bill_month_relabel_collision: bill % (user %, card %) would relabel from % to %, which already exists for this card',
        rec.id, rec.user_id, rec.card_id, rec.bill_month, new_month;
    end if;

    update public.card_bills
      set bill_month = new_month
      where id = rec.id and user_id = rec.user_id;
    updated_count := updated_count + 1;
  end loop;

  raise notice 'card_bill_month_relabel: updated % bill(s)', updated_count;
end
$$;
