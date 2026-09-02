begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

select ok(
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'user_settings'
      and column_name = 'line_pay_qr_data'
  ),
  'LINE Pay QR setting column was removed'
);
select ok(
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'user_settings'
      and column_name = 'line_reminders_enabled'
  ),
  'LINE reminder setting column was removed'
);
select is(to_regclass('public.ocr_import_usage'), null::regclass, 'OCR usage table was removed');
select is(to_regclass('public.line_import_sessions'), null::regclass, 'LINE import sessions were removed');
select is(to_regclass('public.line_import_images'), null::regclass, 'LINE import images were removed');
select is(to_regclass('public.line_ocr_jobs'), null::regclass, 'LINE OCR jobs were removed');
select is(
  to_regprocedure('public.consume_ocr_quota(uuid)'),
  null::regprocedure,
  'OCR quota RPC was removed'
);
select is(
  (select count(*) from storage.buckets where id = 'line-imports'),
  0::bigint,
  'LINE import storage bucket was removed'
);
select ok(
  position('linePayQrData' in public.load_finance_data_v4()::text) = 0
    and position('lineRemindersEnabled' in public.load_finance_data_v4()::text) = 0,
  'finance payload no longer exposes retired LINE settings'
);

select * from finish();
rollback;
