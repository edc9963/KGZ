create table if not exists public.ocr_import_usage (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create index if not exists ocr_import_usage_user_created_idx
  on public.ocr_import_usage (user_id, created_at desc);

alter table public.ocr_import_usage enable row level security;
revoke all on public.ocr_import_usage from anon, authenticated;

create or replace function public.consume_ocr_quota(p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  hourly_count integer;
  daily_count integer;
begin
  select
    count(*) filter (where created_at >= now() - interval '1 hour'),
    count(*) filter (where created_at >= now() - interval '1 day')
  into hourly_count, daily_count
  from public.ocr_import_usage
  where user_id = p_user_id
    and created_at >= now() - interval '1 day';

  if hourly_count >= 20 or daily_count >= 100 then
    return false;
  end if;

  insert into public.ocr_import_usage(user_id) values (p_user_id);
  return true;
end;
$$;

revoke all on function public.consume_ocr_quota(uuid) from public;
grant execute on function public.consume_ocr_quota(uuid) to service_role;
