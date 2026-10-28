-- Transactional content editing restricted to explicitly authorized administrators.
begin;
alter table public.lessons add column archived_at timestamptz;
create function public.admin_save_material(p_kind text,p_id uuid,p_data jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_id uuid; parent uuid; item jsonb; position integer:=0; correct_count integer;
begin
 if not public.is_admin() then raise exception 'Administrator access required'; end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or length(p_data::text)>50000 then raise exception 'Invalid material'; end if;
 if p_kind in ('exercise','exam_question') and (length(trim(coalesce(p_data->>'prompt',''))) not between 1 and 2000 or length(coalesce(p_data->>'passage',''))>10000) then raise exception 'Provide a question of 1 to 2000 characters and a passage no longer than 10000'; end if;
 if p_kind='section' and (length(trim(coalesce(p_data->>'title',''))) not between 2 and 120 or length(trim(coalesce(p_data->>'content',''))) not between 10 and 10000) then raise exception 'Provide a section heading and useful explanation'; end if;
 if p_kind='lesson' then
 update public.lessons set title=p_data->>'title',description=p_data->>'description',cefr_level=(p_data->>'cefr_level')::public.cefr_level,category=(p_data->>'category')::public.skill_category,
 is_published=case when (p_data->>'archived')::boolean then false else coalesce((p_data->>'is_published')::boolean,false) end,
 archived_at=case when (p_data->>'archived')::boolean then now() else null end,updated_at=now() where id=p_id returning id into v_id;
 elsif p_kind='section' then
 update public.lesson_sections set title=p_data->>'title',content=p_data->>'content' where id=p_id returning id into v_id;
 elsif p_kind='exercise' then
 parent:=(p_data->>'lesson_id')::uuid;
 perform 1 from public.lessons where id=parent and not is_published for update;
 if not found then raise exception 'Unpublish the lesson before editing exercises'; end if;
 if exists(select 1 from public.exercise_attempts a join public.exercises e on e.id=a.exercise_id where e.lesson_id=parent)
 or exists(select 1 from public.lesson_progress where lesson_id=parent) then raise exception 'Create a new lesson version to preserve existing learning progress'; end if;
 if p_id is null then
 select coalesce(max(order_index),0)+1 into position from public.exercises where lesson_id=parent;
 insert into public.exercises(lesson_id,prompt,exercise_type,passage,rubric,order_index) values(parent,p_data->>'prompt',(p_data->>'exercise_type')::public.exercise_type,p_data->>'passage',p_data->>'rubric',position) returning id into v_id;
 else
 update public.exercises set prompt=p_data->>'prompt',exercise_type=(p_data->>'exercise_type')::public.exercise_type,passage=p_data->>'passage',rubric=p_data->>'rubric' where id=p_id and lesson_id=parent returning id into v_id;
 end if;
 if v_id is null then raise exception 'Exercise not found'; end if;
 if p_data->>'exercise_type'='short_response' then
 if length(trim(coalesce(p_data->>'rubric','')))<10 then raise exception 'Provide a useful rubric'; end if;
 else
 if jsonb_typeof(p_data->'options')<>'array' or jsonb_array_length(p_data->'options') not between 2 and 6 then raise exception 'Provide two to six options'; end if;
 select count(*) into correct_count from jsonb_array_elements(p_data->'options') o where (o->>'is_correct')::boolean;
 if correct_count<>1 then raise exception 'Exactly one option must be correct'; end if;
 position:=0;
 for item in select * from jsonb_array_elements(p_data->'options') loop
 position:=position+1;
 if length(trim(coalesce(item->>'option_text','')))=0 then raise exception 'Option text is required'; end if;
 if length(trim(coalesce(item->>'explanation','')))<5 then raise exception 'Provide an explanation for each option'; end if;
 insert into public.exercise_options(exercise_id,option_text,is_correct,explanation,order_index)
 values(v_id,item->>'option_text',(item->>'is_correct')::boolean,coalesce(item->>'explanation',''),position)
 on conflict(exercise_id,order_index) do update set option_text=excluded.option_text,is_correct=excluded.is_correct,explanation=excluded.explanation;
 end loop;
 if exists(select 1 from public.exercise_options where exercise_id=v_id and order_index>position) then raise exception 'Keep the existing option count to preserve historical answers'; end if;
 end if;
 elsif p_kind='exam_question' then
 perform 1 from public.exam_sets where id=(select exam_id from public.exam_questions where id=p_id) and not is_published for update;
 if not found then raise exception 'Unpublish the practice set before editing questions'; end if;
 if exists(select 1 from public.exam_attempts a join public.exam_questions q on q.exam_id=a.exam_id where q.id=p_id) then raise exception 'Create a new practice set to preserve existing attempt content'; end if;
 update public.exam_questions set prompt=p_data->>'prompt',passage=p_data->>'passage',rubric=p_data->>'rubric' where id=p_id returning id into v_id;
 for item in select * from jsonb_array_elements(coalesce(p_data->'options','[]')) loop
 update public.exam_question_options set option_text=item->>'option_text',is_correct=(item->>'is_correct')::boolean,explanation=coalesce(item->>'explanation','') where id=(item->>'id')::uuid and question_id=p_id;
 if not found then raise exception 'Option does not belong to this question'; end if;
 end loop;
 if exists(select 1 from public.exam_questions where id=p_id and is_objective) and (select count(*) from public.exam_question_options where question_id=p_id and is_correct)<>1 then raise exception 'Exactly one correct option required'; end if;
 if exists(select 1 from public.exam_attempts a join public.exam_questions q on q.exam_id=a.exam_id where q.id=p_id and a.status='in_progress') then raise exception 'Wait until active attempts end before editing'; end if;
 else raise exception 'Unknown material type'; end if;
 if v_id is null then raise exception 'Material not found'; end if;
 return v_id;
end $$;
revoke all on function public.admin_save_material(text,uuid,jsonb) from public,anon;
grant execute on function public.admin_save_material(text,uuid,jsonb) to authenticated;
-- Existing direct content policies now require admin, including former moderator access.
do $$ declare p record; begin
 for p in select tablename,policyname,cmd from pg_policies where schemaname='public' and tablename in ('lessons','lesson_sections','exercises','exercise_options','exam_questions','exam_question_options') and (policyname like '%staff%' or cmd<>'SELECT') loop
 execute format('drop policy %I on public.%I',p.policyname,p.tablename);
 end loop;
end $$;
create policy admin_lessons on public.lessons for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy admin_sections on public.lesson_sections for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy admin_exercises on public.exercises for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy admin_options on public.exercise_options for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy admin_questions on public.exam_questions for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy admin_exam_options on public.exam_question_options for all to authenticated using(public.is_admin()) with check(public.is_admin());
revoke insert,update on public.exercises,public.exercise_options,public.exam_questions,public.exam_question_options from authenticated;
commit;
