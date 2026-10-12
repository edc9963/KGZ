begin;
create extension if not exists pgtap with schema extensions;
select plan(2);

-- Every project function in public that a client role can execute. Any new
-- client-facing RPC must be added here deliberately; service-role-only
-- functions (LINE bot, reminders, schedulers) must never appear.
create temporary view client_callable_functions as
select r.rolname, p.oid::regprocedure::text as signature
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join pg_roles r
where n.nspname = 'public'
  and p.prokind = 'f'
  and r.rolname in ('anon', 'authenticated')
  and has_function_privilege(r.oid, p.oid, 'execute')
  and not exists (
    select 1 from pg_depend d
    where d.classid = 'pg_proc'::regclass
      and d.objid = p.oid
      and d.deptype = 'e'
  );

select set_eq(
  $$select signature from client_callable_functions where rolname = 'anon'$$,
  array[
    'load_public_collection(text)',
    'mark_public_collection_pending(text)'
  ],
  'anon can execute only the public collection RPCs'
);

select set_eq(
  $$select signature from client_callable_functions where rolname = 'authenticated'$$,
  array[
    'load_finance_data()',
    'save_finance_data(bigint,jsonb)',
    'clear_finance_data(bigint)',
    'load_public_collection(text)',
    'mark_public_collection_pending(text)'
  ],
  'authenticated can execute only the web app RPCs'
);

select * from finish();
rollback;
