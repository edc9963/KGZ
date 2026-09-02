-- Retire the unshipped LINE server-side OCR flow and two settings that never
-- had a production consumer. Browser-side receipt OCR is unaffected.

do $$
begin
  if exists (select 1 from public.ocr_import_usage limit 1)
     or exists (select 1 from public.line_import_sessions limit 1)
     or exists (select 1 from public.line_import_images limit 1)
     or exists (select 1 from public.line_ocr_jobs limit 1) then
    raise exception 'retired_line_ocr_contains_data';
  end if;
  if exists (
    select 1 from storage.objects where bucket_id = 'line-imports' limit 1
  ) then
    raise exception 'retired_line_ocr_bucket_contains_objects';
  end if;
  if exists (
    select 1 from public.user_settings
    where line_pay_qr_data <> '' or line_reminders_enabled
    limit 1
  ) then
    raise exception 'retired_user_settings_contain_values';
  end if;
end
$$;

-- The current RPC is a wrapper chain whose base implementation is still the
-- v4 function. Rewrite only the two retired JSON properties and make the
-- settings insert column-explicit before dropping the physical columns.
do $$
declare
  source text;
  rewritten text;
begin
  source := pg_get_functiondef('public.load_finance_data_v4()'::regprocedure);
  rewritten := replace(
    replace(
      source,
      '''linePayQrData'', s.line_pay_qr_data,' || chr(10),
      ''
    ),
    '''lineRemindersEnabled'', s.line_reminders_enabled,' || chr(10),
    ''
  );
  if rewritten = source
     or position('line_pay_qr_data' in rewritten) > 0
     or position('line_reminders_enabled' in rewritten) > 0 then
    raise exception 'load_finance_data_v4_rewrite_pattern_not_found';
  end if;
  execute rewritten;

  source := pg_get_functiondef(
    'public.save_finance_data_v4(bigint,jsonb)'::regprocedure
  );
  rewritten := replace(
    source,
    'insert into public.user_settings values (',
    'insert into public.user_settings(' ||
    'user_id, default_currency, default_payment_method, default_category, ' ||
    'default_collection_account_id, bank_qr_data, bank_account_info, ' ||
    'reminders_enabled, mask_balances) values ('
  );
  rewritten := replace(
    rewritten,
    'coalesce(item->>''linePayQrData'', ''''), ',
    ''
  );
  rewritten := replace(
    rewritten,
    'coalesce((item->>''lineRemindersEnabled'')::boolean, false),' || chr(10),
    ''
  );
  if rewritten = source
     or position('linePayQrData' in rewritten) > 0
     or position('lineRemindersEnabled' in rewritten) > 0
     or position('insert into public.user_settings values (' in rewritten) > 0 then
    raise exception 'save_finance_data_v4_rewrite_pattern_not_found';
  end if;
  execute rewritten;
end
$$;

alter table public.user_settings drop column line_pay_qr_data;
alter table public.user_settings drop column line_reminders_enabled;

drop function public.consume_ocr_quota(uuid);
drop table public.ocr_import_usage;
drop table public.line_ocr_jobs;
drop table public.line_import_images;
drop table public.line_import_sessions;

-- Storage protects its metadata tables from direct deletion. The bucket is
-- known to be empty from the guard above, so allow this narrowly scoped
-- metadata delete for the remainder of the current migration transaction.
do $$
begin
  if exists (
    select 1 from storage.buckets where id = 'line-imports'
  ) then
    perform set_config('storage.allow_delete_query', 'true', true);
    delete from storage.buckets where id = 'line-imports';
  end if;
end
$$;
