-- Isolated test database ONLY: original migrations 1-3 plus the standalone hotfix.
-- Creates a fixture account and tests actual submission; all fixture changes roll back.
begin;
insert into auth.users(id,email,raw_user_meta_data) values('00000000-0000-4000-8000-000000000088','enum-regression@fluentpath.invalid','{"full_name":"Enum regression"}');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000088',true);
set local role authenticated;
do $$ declare payload jsonb; item jsonb; chosen uuid; result jsonb; state public.progress_status; reward integer;
begin
 if pg_typeof(case when true then 'completed'::public.progress_status else 'in_progress'::public.progress_status end)<>'public.progress_status'::regtype then raise exception 'CASE is not enum typed'; end if;
 payload:=public.get_lesson('a1-verb-to-be'); item:=payload->'exercises'->0;
 select (o->>'id')::uuid into chosen from jsonb_array_elements(item->'options') o where o->>'option_text'='are';
 if chosen is null then raise exception 'Expected seeded choice missing'; end if;
 result:=public.submit_exercise((item->>'id')::uuid,chosen);
 if (result->>'correct')::boolean is distinct from true then raise exception 'Correct submission failed: %',result; end if;
 select status into state from public.lesson_progress where lesson_id=(payload->'lesson'->>'id')::uuid;
 if state is distinct from 'completed'::public.progress_status then raise exception 'Completion was not persisted'; end if;
 select total_xp into reward from public.profiles where id=auth.uid();
 if reward<=0 then raise exception 'XP was not persisted'; end if;
 -- Exercise the ON CONFLICT branch with an already completed lesson; preserve completion.
 result:=public.submit_exercise((item->>'id')::uuid,chosen);
 if (result->>'correct')::boolean is distinct from true or (result->>'xp_awarded')::integer<>0 then raise exception 'Repeat submission failed or duplicated XP'; end if;
 select status into state from public.lesson_progress where lesson_id=(payload->'lesson'->>'id')::uuid;
 if state is distinct from 'completed'::public.progress_status then raise exception 'Repeat downgraded progress'; end if;
 -- Start a second lesson with a wrong choice, then retry the right choice.
 payload:=public.get_lesson('a1-cafe-vocabulary'); item:=payload->'exercises'->0;
 select (o->>'id')::uuid into chosen from jsonb_array_elements(item->'options') o where o->>'option_text'='Give a tea.';
 result:=public.submit_exercise((item->>'id')::uuid,chosen);
 if (result->>'correct')::boolean is distinct from false then raise exception 'Incorrect submission was not marked false'; end if;
 select status into state from public.lesson_progress where lesson_id=(payload->'lesson'->>'id')::uuid;
 if state is distinct from 'in_progress'::public.progress_status then raise exception 'In-progress enum assignment failed'; end if;
 select (o->>'id')::uuid into chosen from jsonb_array_elements(item->'options') o where o->>'option_text'='Could I have a tea, please?';
 result:=public.submit_exercise((item->>'id')::uuid,chosen);
 if (result->>'correct')::boolean is distinct from true then raise exception 'Retry failed'; end if;
end $$;
rollback;
