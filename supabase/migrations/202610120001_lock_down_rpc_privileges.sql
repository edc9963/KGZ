-- Supabase's default privileges grant EXECUTE on every new public function
-- to anon and authenticated directly, so the earlier `revoke ... from public`
-- statements left the service-role-only LINE, reminder and scheduler RPCs
-- callable through PostgREST by anyone who knew (or guessed) a LINE user id.
--
-- Revoke EXECUTE on every project function in the public schema from the
-- client roles, then re-grant only the RPCs the web app actually calls.
-- service_role keeps its grants, so Edge Functions and pg_cron are unaffected.

do $$
declare
  fn regprocedure;
begin
  for fn in
    select p.oid::regprocedure
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
      -- Leave extension-owned functions to their extensions.
      and not exists (
        select 1 from pg_depend d
        where d.classid = 'pg_proc'::regclass
          and d.objid = p.oid
          and d.deptype = 'e'
      )
  loop
    execute format(
      'revoke execute on function %s from public, anon, authenticated',
      fn
    );
  end loop;
end
$$;

grant execute on function public.load_finance_data() to authenticated;
grant execute on function public.save_finance_data(bigint, jsonb) to authenticated;
grant execute on function public.clear_finance_data(bigint) to authenticated;
grant execute on function public.load_public_collection(text) to anon, authenticated;
grant execute on function public.mark_public_collection_pending(text) to anon, authenticated;

-- Future functions created by this migration role start without client
-- access; every client-facing RPC must be granted explicitly, as above.
alter default privileges in schema public
  revoke execute on functions from public, anon, authenticated;
