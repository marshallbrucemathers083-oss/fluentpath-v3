-- OWNER REVIEW + APPROVAL REQUIRED. Containment only after all four bundles committed.
-- Retains users, progress, XP, achievements, audit history and security protections.
begin;
do $$ begin
 if not exists(select 1 from supabase_migrations.schema_migrations where version='20261028120007') then raise exception 'Partial release: inspect committed state before choosing containment'; end if;
end $$;
update public.lessons set is_published=false where slug ~ '^(a1|a2|b1|b2|c1|c2)-(grammar|vocabulary|reading|listening|writing|speaking)-scenario-workshop$';
update public.exam_sets set is_published=false where title='Academic evidence and decisions';
revoke execute on function public.admin_save_material(text,uuid,jsonb),public.admin_create_practice(jsonb),public.admin_set_practice_status(uuid,boolean) from authenticated;
commit;
