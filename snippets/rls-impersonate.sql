-- RLS impersonation: see exactly what PostgREST would let a user (or anon) see,
-- then throw everything away. Each block below has no blank lines inside it, so put the
-- cursor anywhere in a block and press  space , r  to run the whole transaction.
-- Needs a direct or session-mode connection (port 5432), not the transaction pooler.

-- 1 · who to be (run this block once, or edit and re-run)
\set uid '00000000-0000-0000-0000-000000000000'
\set email 'someone@example.com'

-- 2 · as an authenticated user
begin;
select set_config('request.jwt.claims',
                  json_build_object('sub', :'uid', 'role', 'authenticated', 'email', :'email')::text,
                  true);
set local role authenticated;
select current_user, auth.uid(), auth.role();          -- sanity check
-- your checks, e.g.
-- select count(*) from public.some_table;
-- insert into public.some_table (...) values (...) returning *;   -- write paths too
rollback;

-- 3 · as anon (no JWT subject)
begin;
select set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
set local role anon;
select current_user, auth.uid();                        -- expect anon, ∅
-- select count(*) from public.some_table;
rollback;

-- 4 · what can each API role reach at all? (table privileges, before RLS applies)
select grantee, table_schema, table_name, string_agg(privilege_type, ', ' order by privilege_type) as privileges
  from information_schema.role_table_grants
 where grantee in ('anon', 'authenticated')
   and table_schema not in ('pg_catalog', 'information_schema')
 group by 1, 2, 3
 order by 2, 3, 1;
