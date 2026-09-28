-- RLS isolation check (run against a local db: docker exec -i supabase_db_arivo psql -U postgres -v ON_ERROR_STOP=1 < supabase/tests/rls_check.sql)
begin;
delete from arivo.trips where id = 'trp_rls';
insert into auth.users (id, email) values ('00000000-0000-0000-0000-00000000000a','alice@x'),('00000000-0000-0000-0000-00000000000b','mallory@x'),('00000000-0000-0000-0000-00000000000c','vic@x') on conflict do nothing;
insert into arivo.users (id, display_name) values ('00000000-0000-0000-0000-00000000000a','Alice'),('00000000-0000-0000-0000-00000000000b','Mallory'),('00000000-0000-0000-0000-00000000000c','Vic') on conflict do nothing;
insert into arivo.trips (id, owner_id, title, start_date, timezone, currency, home_currency, doc) values ('trp_rls','00000000-0000-0000-0000-00000000000a','T','2026-11-16','Asia/Tokyo','JPY','MYR','{}');
insert into arivo.trip_members values ('trp_rls','00000000-0000-0000-0000-00000000000c','viewer',2,false,now());
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000b","role":"authenticated"}', true);
do $$ begin if (select count(*) from arivo.trips) <> 0 then raise exception 'BOLA: stranger can read a trip'; end if; end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000c","role":"authenticated"}', true);
do $$ begin if (select count(*) from arivo.trips) <> 1 then raise exception 'viewer cannot read'; end if; end $$;
update arivo.trips set title = 'hacked' where id = 'trp_rls';
do $$ begin if (select title from arivo.trips where id = 'trp_rls') <> 'T' then raise exception 'viewer could write'; end if; end $$;
select 'RLS OK';
rollback;
