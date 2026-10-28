-- Read-only assertions after the complete release; not a replacement for authenticated tests.
do $$ declare fn text; begin
 if (select count(*) from supabase_migrations.schema_migrations where version in ('20261028120004','20261028120005','20261028120006','20261028120007'))<>4 then raise exception 'Missing release history'; end if;
 if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='profiles' and column_name='suspended_until') then raise exception 'Missing suspension column'; end if;
 if exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and not c.relrowsecurity) then raise exception 'Application table lacks RLS'; end if;
 if has_table_privilege('authenticated','public.profiles','UPDATE') or has_table_privilege('authenticated','public.exercise_options','INSERT') or has_table_privilege('authenticated','public.moderation_history','INSERT') then raise exception 'Excess client write grants'; end if;
 foreach fn in array array['public.admin_save_material(text,uuid,jsonb)','public.admin_moderate_user(uuid,text,text,timestamptz)','public.admin_create_practice(jsonb)','public.admin_set_practice_status(uuid,boolean)','public.admin_report_context(uuid)','public.admin_platform_stats()'] loop
 if to_regprocedure(fn) is null or has_function_privilege('anon',fn,'EXECUTE') or not has_function_privilege('authenticated',fn,'EXECUTE') then raise exception 'Unexpected RPC grants: %',fn; end if;
 end loop;
 if (select count(*) from public.lessons where slug ~ '^(a1|a2|b1|b2|c1|c2)-(grammar|vocabulary|reading|listening|writing|speaking)-scenario-workshop$')<>36 then raise exception 'Curriculum release incomplete'; end if;
end $$;
select version,name from supabase_migrations.schema_migrations order by version;
