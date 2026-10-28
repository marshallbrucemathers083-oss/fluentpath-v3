-- Complete administrator workflows without granting student write access.
begin;
create function public.admin_platform_stats() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'Administrator access required'; end if;
 return jsonb_build_object(
 'users',(select count(*) from public.profiles),
 'restricted_users',(select count(*) from public.profiles where is_banned or suspended_until>now()),
 'lessons',(select count(*) from public.lessons),
 'published_lessons',(select count(*) from public.lessons where is_published),
 'completed_lessons',(select count(*) from public.lesson_progress where status='completed'),
 'completed_practice',(select count(*) from public.exam_attempts where status='completed'),
 'pending_reports',(select count(*) from public.forum_reports where status='open'));
end $$;
create function public.admin_create_practice(p_data jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare result uuid; parent uuid; item jsonb; objective boolean; pos integer;
begin
 if not public.is_admin() then raise exception 'Administrator access required'; end if;
 if p_data is null or length(p_data::text)>50000 then raise exception 'Invalid practice data'; end if;
 if p_data->>'kind'='set' and (length(trim(coalesce(p_data->>'title',''))) not between 2 and 120 or length(coalesce(p_data->>'description',''))>1000) then raise exception 'Provide a title of 2 to 120 characters and a description no longer than 1000'; end if;
 if p_data->>'kind'='question' and (length(trim(coalesce(p_data->>'prompt',''))) not between 1 and 2000 or length(coalesce(p_data->>'passage',''))>10000) then raise exception 'Provide a question and a passage no longer than 10000 characters'; end if;
 if p_data->>'kind'='set' then
 insert into public.exam_sets(title,description,cefr_level,duration_seconds,is_published)
 values(p_data->>'title',p_data->>'description',(p_data->>'cefr_level')::public.cefr_level,(p_data->>'duration_seconds')::integer,false) returning id into result;
 elsif p_data->>'kind'='question' then
 parent:=(p_data->>'exam_id')::uuid;
 perform 1 from public.exam_sets where id=parent and not is_published for update;
 if not found then raise exception 'Choose an unpublished practice set'; end if;
 if exists(select 1 from public.exam_attempts where exam_id=parent) then raise exception 'Create a new set instead of changing an attempted set'; end if;
 objective:=coalesce((p_data->>'is_objective')::boolean,true);
 if objective and (jsonb_array_length(coalesce(p_data->'options','[]')) not between 2 and 6 or (select count(*) from jsonb_array_elements(p_data->'options') o where (o->>'is_correct')::boolean)<>1) then raise exception 'Provide two to six options with exactly one correct answer'; end if;
 if not objective and length(trim(coalesce(p_data->>'rubric','')))<10 then raise exception 'Provide a useful practice rubric'; end if;
 select coalesce(max(order_index),0)+1 into pos from public.exam_questions where exam_id=parent;
 insert into public.exam_questions(exam_id,category,prompt,passage,rubric,is_objective,order_index)
 values(parent,(p_data->>'category')::public.skill_category,p_data->>'prompt',p_data->>'passage',p_data->>'rubric',objective,pos) returning id into result;
 if objective then
 pos:=0;
 for item in select * from jsonb_array_elements(p_data->'options') loop
 pos:=pos+1;
 if length(trim(coalesce(item->>'option_text','')))=0 then raise exception 'Option text is required'; end if;
 if length(trim(coalesce(item->>'explanation','')))<5 then raise exception 'Provide an explanation for each option'; end if;
 insert into public.exam_question_options(question_id,option_text,is_correct,explanation,order_index) values(result,item->>'option_text',(item->>'is_correct')::boolean,coalesce(item->>'explanation',''),pos);
 end loop;
 end if;
 else raise exception 'Invalid practice kind'; end if;
 return result;
end $$;
create function public.admin_set_practice_status(p_id uuid,p_published boolean) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'Administrator access required'; end if;
 perform 1 from public.exam_sets where id=p_id for update;
 if not found then raise exception 'Practice set not found'; end if;
 if p_published and (not exists(select 1 from public.exam_questions where exam_id=p_id and is_objective) or exists(
 select 1 from public.exam_questions q where q.exam_id=p_id and q.is_objective and ((select count(*) from public.exam_question_options where question_id=q.id)<2 or (select count(*) from public.exam_question_options where question_id=q.id and is_correct)<>1))) then raise exception 'Add complete objective questions before publishing'; end if;
 update public.exam_sets set is_published=p_published where id=p_id;
end $$;
create function public.admin_report_context(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare r public.forum_reports%rowtype; content jsonb; parent jsonb; subject uuid;
begin
 if not public.is_admin() then raise exception 'Administrator access required'; end if;
 select * into r from public.forum_reports where id=p_id;
 if not found then raise exception 'Report not found'; end if;
 if r.content_type='thread' then
 select to_jsonb(t),t.user_id into content,subject from public.forum_threads t where id=r.content_id;
 else
 select to_jsonb(c),c.user_id into content,subject from public.forum_replies c where id=r.content_id;
 select to_jsonb(t) into parent from public.forum_threads t where id=(content->>'thread_id')::uuid;
 end if;
 return jsonb_build_object('report',to_jsonb(r)-'reporter_id','content',content,'parent',parent,
 'author',(select jsonb_build_object('id',id,'full_name',full_name,'is_banned',is_banned,'suspended_until',suspended_until) from public.profiles where id=subject),
 'warnings',(select coalesce(jsonb_agg(jsonb_build_object('reason',reason,'created_at',created_at)),'[]') from public.user_warnings where user_id=subject));
end $$;
create policy admin_exam_sets_read on public.exam_sets for select to authenticated using(public.is_admin());
revoke all on function public.admin_platform_stats(),public.admin_create_practice(jsonb),public.admin_set_practice_status(uuid,boolean),public.admin_report_context(uuid) from public,anon;
grant execute on function public.admin_platform_stats(),public.admin_create_practice(jsonb),public.admin_set_practice_status(uuid,boolean),public.admin_report_context(uuid) to authenticated;
create or replace function public.moderate_forum_report(p_report_id uuid,p_decision text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'Administrator access required'; end if;
 if p_decision not in ('resolve','dismiss') then raise exception 'Invalid decision'; end if;
 update public.forum_reports set status=case when p_decision='resolve' then 'resolved' else 'dismissed' end,moderator_id=auth.uid(),resolved_at=now() where id=p_report_id and status='open';
 if not found then raise exception 'Open report not found'; end if;
end $$;
create or replace function public.moderate_forum_content(p_content_type text,p_content_id uuid,p_status text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'Administrator access required'; end if;
 if p_status not in ('published','hidden','removed') then raise exception 'Invalid status'; end if;
 if p_content_type='thread' then update public.forum_threads set status=p_status,updated_at=now() where id=p_content_id;
 elsif p_content_type='reply' then update public.forum_replies set status=p_status where id=p_content_id;
 else raise exception 'Invalid content type'; end if;
 if not found then raise exception 'Content not found'; end if;
end $$;
revoke insert,update on public.exercises,public.exercise_options,public.exam_questions,public.exam_question_options from authenticated;
create or replace function public.admin_set_user_ban(p_user_id uuid,p_is_banned boolean) returns void
language plpgsql security definer set search_path='' as $$
begin
 if p_is_banned is null then raise exception 'Choose ban or restore'; end if;
 perform public.admin_moderate_user(p_user_id,case when p_is_banned then 'ban' else 'restore' end,'Administrator member access control');
end $$;
drop policy report_read on public.forum_reports;
create policy reports_admin_read on public.forum_reports for select to authenticated using(public.is_admin());
drop policy warning_read on public.user_warnings;
create policy warnings_private_read on public.user_warnings for select to authenticated using(user_id=auth.uid() or public.is_admin());
create function private.validate_archive_state() returns trigger language plpgsql set search_path='' as $$
begin
 if new.archived_at is not null and new.is_published then raise exception 'Restore an archived lesson before publishing'; end if;
 return new;
end $$;
revoke all on function private.validate_archive_state() from public,anon,authenticated;
create trigger lesson_archive_state before insert or update of is_published,archived_at on public.lessons for each row execute function private.validate_archive_state();
commit;
