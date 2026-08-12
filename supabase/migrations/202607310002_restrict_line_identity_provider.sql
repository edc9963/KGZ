-- A provider_id is only meaningful inside its identity provider. Restrict the
-- Bot lookup to the configured LINE custom OIDC provider so another provider
-- can never be linked merely because its identifier text happens to match.
create or replace function public.line_owner_id(p_line_user_id text)
returns uuid
language sql
stable
security definer
set search_path = public, auth, pg_temp
as $$
  select i.user_id
  from auth.identities i
  where i.provider_id = p_line_user_id
    and i.provider = 'custom:line'
  order by i.created_at
  limit 1
$$;

revoke all on function public.line_owner_id(text) from public;
grant execute on function public.line_owner_id(text) to service_role;
