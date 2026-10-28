-- Standalone fix for the deployed progress upsert; no admin migrations required.
begin;
do $hotfix$
declare
 definition text;
 broken text := $expression$case when public.lesson_progress.status='completed' then 'completed' else 'in_progress' end$expression$;
 fixed text := $expression$case when public.lesson_progress.status='completed' then 'completed'::public.progress_status else 'in_progress'::public.progress_status end$expression$;
begin
 definition := pg_get_functiondef('public.submit_exercise(uuid,uuid)'::regprocedure);
 if position(broken in definition)>0 then
  -- Preserve the deployed function body, owner, signature, authorization and ACLs.
  execute replace(definition,broken,fixed);
 elsif position(fixed in definition)=0 then
  raise exception 'Unexpected submit_exercise definition; stop and review instead of replacing it';
 end if;
end $hotfix$;
commit;
