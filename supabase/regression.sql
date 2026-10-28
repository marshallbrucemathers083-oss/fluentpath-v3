-- Run only against an isolated test database after all seven migrations. Always rolls back.
begin;
insert into auth.users(id,email,raw_user_meta_data) values('00000000-0000-4000-8000-000000000099','regression@fluentpath.invalid','{"full_name":"Regression learner"}');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000099',true);
do $$ declare e record; o record; result jsonb; xp integer; attempt jsonb; q jsonb; answer uuid;
begin
 for e in select ex.* from public.exercises ex join public.lessons l on l.id=ex.lesson_id where l.is_published and exercise_type<>'short_response' loop
  for o in select * from public.exercise_options where exercise_id=e.id order by is_correct loop
   result:=public.submit_exercise(e.id,o.id);
   if (result->>'correct')::boolean is distinct from o.is_correct then raise exception 'Incorrect validation for exercise % option %',e.id,o.id; end if;
  end loop;
  select id into answer from public.exercise_options where exercise_id=e.id and is_correct;
  result:=public.submit_exercise(e.id,answer);
  if (result->>'xp_awarded')::integer<>0 then raise exception 'Repeat XP award for %',e.id; end if;
 end loop;
 for e in select ex.* from public.exercises ex join public.lessons l on l.id=ex.lesson_id where l.is_published and exercise_type='short_response' loop
  result:=public.submit_written_response(e.id,'A clear response with a specific example and a reason for my recommendation.');
  if result ? 'correct' then raise exception 'Writing was falsely graded'; end if;
 end loop;
 begin
  perform public.admin_moderate_user('00000000-0000-4000-8000-000000000099','ban','Unauthorized action');
  raise exception 'Student moderation unexpectedly succeeded';
 exception when others then
  if sqlerrm<>'Administrator access required' then raise; end if;
 end;
 attempt:=public.start_toefl_attempt();
 for q in select * from jsonb_array_elements(attempt->'questions') loop
  if jsonb_array_length(q->'options')>0 then
   select id into answer from public.exam_question_options where question_id=(q->>'id')::uuid and is_correct;
   perform public.submit_toefl_answer((attempt->>'attempt_id')::uuid,(q->>'id')::uuid,answer::text);
  else
   perform public.submit_toefl_answer((attempt->>'attempt_id')::uuid,(q->>'id')::uuid,'An outline with a claim, supporting evidence and a practical limitation.');
  end if;
 end loop;
 result:=public.finish_toefl_attempt((attempt->>'attempt_id')::uuid);
 if (result->>'score_percentage')::integer<>100 then raise exception 'Correct exam answers did not score 100: %',result; end if;
end $$;
do $$ declare attempt jsonb; q jsonb; answer uuid; result jsonb; member uuid:='00000000-0000-4000-8000-000000000100'; thread uuid; first_report uuid; second_report uuid;
begin
 attempt:=public.start_toefl_attempt();
 for q in select * from jsonb_array_elements(attempt->'questions') loop
  if jsonb_array_length(q->'options')>0 then
   select id into answer from public.exam_question_options where question_id=(q->>'id')::uuid and not is_correct order by order_index limit 1;
   perform public.submit_toefl_answer((attempt->>'attempt_id')::uuid,(q->>'id')::uuid,answer::text);
  else perform public.submit_toefl_answer((attempt->>'attempt_id')::uuid,(q->>'id')::uuid,'Practice response, deliberately ungraded.'); end if;
 end loop;
 result:=public.finish_toefl_attempt((attempt->>'attempt_id')::uuid);
 if (result->>'score_percentage')::integer<>0 then raise exception 'Incorrect exam answers did not score zero'; end if;
 insert into auth.users(id,email,raw_user_meta_data) values(member,'moderation-regression@fluentpath.invalid','{"full_name":"Moderation fixture","role":"admin"}');
 if (select role from public.profiles where id=member)<>'student' then raise exception 'Signup metadata escalated privileges'; end if;
 update public.profiles set role='admin' where id=auth.uid();
 perform set_config('request.jwt.claim.sub','',true);
 update public.profiles set role='admin' where id='00000000-0000-4000-8000-000000000099';
 if not exists(select 1 from public.moderation_history where target_id='00000000-0000-4000-8000-000000000099' and actor_id is null and actor_database_role is not null) then raise exception 'Trusted owner role change was not audited'; end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000099',true);
 perform public.admin_moderate_user(member,'suspend','Temporary test restriction',now()+interval '1 hour');
 perform set_config('request.jwt.claim.sub',member::text,true);
 begin
  perform public.create_forum_thread('Restricted post','This account should not be allowed to publish this post.');
  raise exception 'Suspended account posted';
 exception when others then if sqlerrm<>'Account access restricted' then raise; end if; end;
 perform set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000099',true);
 perform public.admin_moderate_user(member,'restore','Restoring test account');
 perform public.admin_moderate_user(member,'suspend','Testing legacy restoration',now()+interval '1 hour');
 perform public.admin_set_user_ban(member,false);
 if exists(select 1 from public.profiles where id=member and (is_banned or suspended_until is not null)) then raise exception 'Legacy restore left a restriction active'; end if;
 perform set_config('request.jwt.claim.sub',member::text,true);
 thread:=public.create_forum_thread('A restored account','Posting is permitted again after an administrator restores access.');
 first_report:=public.report_forum_content('thread',thread,'Spam or advertising: test report');
 second_report:=public.report_forum_content('thread',thread,'Spam or advertising: duplicate');
 if first_report<>second_report then raise exception 'Duplicate report was created'; end if;
 if (select is_banned from public.profiles where id=member) then raise exception 'Report automatically banned a member'; end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000099',true);
 perform public.moderate_forum_report(first_report,'dismiss');
 if not exists(select 1 from public.moderation_history where target_id=first_report) then raise exception 'Missing moderation audit'; end if;
 perform public.admin_moderate_user(member,'ban','Testing permanent restriction');
 perform set_config('request.jwt.claim.sub',member::text,true);
 if public.account_active() then raise exception 'Banned account remains active'; end if;
end $$;
set local role authenticated;
do $$ begin
 if exists(select 1 from public.exercise_options) or exists(select 1 from public.exam_question_options) then raise exception 'Student can read keys'; end if;
 if exists(select 1 from public.moderation_history) then raise exception 'Student can read moderation history'; end if;
end $$;
rollback;
