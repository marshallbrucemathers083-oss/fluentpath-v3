-- Submission consistency, access restrictions and moderation audit.
begin;

alter table public.profiles add column suspended_until timestamptz;
create function public.account_active() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles where id=auth.uid() and not is_banned and (suspended_until is null or suspended_until<=now()))
$$;
revoke all on function public.account_active() from public,anon;
grant execute on function public.account_active() to authenticated;
create table public.moderation_history (
 id uuid primary key default gen_random_uuid(), actor_id uuid references public.profiles(id),
 actor_database_role text not null default session_user,
 target_id uuid, action text not null, details jsonb not null, created_at timestamptz not null default now()
);
alter table public.moderation_history enable row level security;
revoke all on public.moderation_history from public,anon,authenticated;
create policy history_admin_read on public.moderation_history for select to authenticated using(public.is_admin());
grant select on public.moderation_history to authenticated;
create policy report_own_read on public.forum_reports for select to authenticated using(reporter_id=auth.uid());
create unique index report_one_open_per_member on public.forum_reports(reporter_id,content_type,content_id) where status='open';

create or replace function public.is_staff() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles where id=auth.uid() and role in ('admin','moderator') and not is_banned and (suspended_until is null or suspended_until<=now()))
$$;

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles where id=auth.uid() and role='admin' and not is_banned and (suspended_until is null or suspended_until<=now()))
$$;

create or replace function public.submit_exercise(p_exercise_id uuid,p_option_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); lesson uuid; correct boolean; feedback text; points integer; earned integer:=0; done_xp integer:=0; quest_xp integer:=0; completed boolean:=false; score integer; first_today boolean;
begin
 perform 1 from public.profiles where id=u for update;
 if not public.account_active() then raise exception 'Account access restricted'; end if;
 if u is null then raise exception 'Sign in required'; end if;
 if exists(select 1 from public.profiles where id=u and is_banned) then raise exception 'Account is suspended'; end if;
 select e.lesson_id,e.points into lesson,points from public.exercises e join public.lessons l on l.id=e.lesson_id
  where e.id=p_exercise_id and l.is_published and e.exercise_type<>'short_response';
 if not found then raise exception 'Exercise not found'; end if;
 perform 1 from public.lessons where id=lesson and is_published for share;
 if not found then raise exception 'Lesson is no longer published'; end if;
 select o.is_correct,o.explanation into correct,feedback from public.exercise_options o where o.id=p_option_id and o.exercise_id=p_exercise_id;
 if not found then raise exception 'Answer is not part of this exercise'; end if;
 select not exists(select 1 from public.exercise_attempts a where a.user_id=u and a.exercise_id=p_exercise_id and a.is_correct=true and a.created_at::date=current_date) into first_today;
 insert into public.exercise_attempts(user_id,exercise_id,submitted_answer,is_correct,points_earned)
 values(u,p_exercise_id,p_option_id::text,correct,case when correct then points else 0 end);
 insert into public.lesson_progress(user_id,lesson_id,status) values(u,lesson,'in_progress')
 on conflict(user_id,lesson_id) do update set status=case when public.lesson_progress.status='completed' then 'completed'::public.progress_status else 'in_progress'::public.progress_status end,updated_at=now();
 if correct then earned:=private.grant_xp(u,least(points,30),'exercise',p_exercise_id::text,'Correct exercise answer'); end if;
 if not exists(select 1 from public.exercises e where e.lesson_id=lesson and not exists(
  select 1 from public.exercise_attempts a where a.user_id=u and a.exercise_id=e.id and (a.is_correct=true or (a.is_correct is null and e.exercise_type='short_response'))))
 then
  select coalesce(floor(100.0*count(*) filter(where exists(select 1 from public.exercise_attempts a where a.user_id=u and a.exercise_id=e.id and (a.is_correct=true or a.is_correct is null)))/nullif(count(*),0)),100)::integer
  into score from public.exercises e where e.lesson_id=lesson;
  update public.lesson_progress set status='completed',score_percentage=score,completed_at=coalesce(completed_at,now()),updated_at=now() where user_id=u and lesson_id=lesson;
  done_xp:=private.grant_xp(u,(select xp_reward from public.lessons where id=lesson),'lesson_completion',lesson::text,'Lesson completed');
  insert into public.user_achievements(user_id,achievement_id) select u,id from public.achievements where slug='first-lesson' on conflict do nothing;
  if found then earned:=earned+private.grant_xp(u,50,'achievement','first-lesson','First lesson achievement'); end if;
  if score=100 and not exists(select 1 from public.exercise_attempts a join public.exercises e on e.id=a.exercise_id where a.user_id=u and e.lesson_id=lesson and a.is_correct=false) and not exists(select 1 from public.exercises where lesson_id=lesson and exercise_type='short_response') then
   insert into public.user_achievements(user_id,achievement_id) select u,id from public.achievements where slug='perfect-practice' on conflict do nothing;
   if found then earned:=earned+private.grant_xp(u,40,'achievement','perfect-practice','Perfect practice achievement'); end if;
  end if;
  completed:=true;
 end if;
 quest_xp:=private.advance_quests(u,case when correct and first_today then 1 else 0 end,earned+done_xp);
 return jsonb_build_object('correct',correct,'feedback',coalesce(feedback,''),'xp_awarded',earned+done_xp+quest_xp,'lesson_completed',completed);
end $$;

create or replace function public.submit_written_response(p_exercise_id uuid,p_response text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); lesson uuid; guidance text; earned integer; done_xp integer:=0; quest_xp integer:=0; completed boolean:=false; first_today boolean;
begin
 perform 1 from public.profiles where id=u for update;
 if not public.account_active() then raise exception 'Account access restricted'; end if;
 if u is null then raise exception 'Sign in required'; end if;
 if exists(select 1 from public.profiles where id=u and is_banned) then raise exception 'Account is suspended'; end if;
 if length(trim(p_response))<20 or length(p_response)>4000 then raise exception 'Write at least 20 characters and no more than 4000'; end if;
 select e.lesson_id,e.rubric into lesson,guidance from public.exercises e join public.lessons l on l.id=e.lesson_id
  where e.id=p_exercise_id and e.exercise_type='short_response' and l.is_published;
 if not found then raise exception 'Writing exercise not found'; end if;
 perform 1 from public.lessons where id=lesson and is_published for share;
 if not found then raise exception 'Lesson is no longer published'; end if;
 select not exists(select 1 from public.exercise_attempts a where a.user_id=u and a.exercise_id=p_exercise_id and a.is_correct is null and a.created_at::date=current_date) into first_today;
 insert into public.exercise_attempts(user_id,exercise_id,submitted_answer,is_correct,points_earned) values(u,p_exercise_id,trim(p_response),null,5);
 insert into public.lesson_progress(user_id,lesson_id,status) values(u,lesson,'in_progress') on conflict(user_id,lesson_id) do update set updated_at=now();
 earned:=private.grant_xp(u,5,'exercise',p_exercise_id::text,'Writing response submitted');
 if not exists(select 1 from public.exercises e where e.lesson_id=lesson and not exists(select 1 from public.exercise_attempts a where a.user_id=u and a.exercise_id=e.id and (a.is_correct=true or a.is_correct is null))) then
  update public.lesson_progress set status='completed',score_percentage=null,completed_at=coalesce(completed_at,now()),updated_at=now() where user_id=u and lesson_id=lesson;
  done_xp:=private.grant_xp(u,(select xp_reward from public.lessons where id=lesson),'lesson_completion',lesson::text,'Lesson completed'); completed:=true;
  insert into public.user_achievements(user_id,achievement_id) select u,id from public.achievements where slug='first-lesson' on conflict do nothing;
  if found then earned:=earned+private.grant_xp(u,50,'achievement','first-lesson','First lesson achievement'); end if;
 end if;
 quest_xp:=private.advance_quests(u,case when first_today then 1 else 0 end,earned+done_xp);
 return jsonb_build_object('feedback',coalesce(guidance,'Review your response for clarity, accurate language, and a clear structure.'),'xp_awarded',earned+done_xp+quest_xp,'lesson_completed',completed);
end $$;

create or replace function public.start_toefl_attempt() returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); exam public.exam_sets%rowtype; attempt uuid; started timestamptz; questions jsonb; saved jsonb; resumed boolean:=false;
begin
 if not public.account_active() then raise exception 'Account access restricted'; end if;
 if u is null then raise exception 'Sign in required'; end if;
 if exists(select 1 from public.profiles where id=u and is_banned) then raise exception 'Account is suspended'; end if;
 perform 1 from public.profiles where id=u for update;
 if not public.account_active() then raise exception 'Account access restricted'; end if;
 select s.* into exam from public.exam_sets s where s.is_published order by (select count(*) from public.exam_attempts a where a.exam_id=s.id and a.user_id=u and a.status='completed'),s.created_at limit 1;
 if not found then raise exception 'No exam has been published yet'; end if;
 perform 1 from public.exam_sets where id=exam.id and is_published for share;
 if not found then raise exception 'Practice set is no longer published'; end if;
 select a.id,a.started_at into attempt,started from public.exam_attempts a where a.user_id=u and a.exam_id=exam.id and a.status='in_progress' order by a.started_at desc limit 1 for update;
 if found and started+exam.duration_seconds*interval '1 second'>now() then resumed:=true;
 elsif found then update public.exam_attempts set status='abandoned' where id=attempt; attempt:=null; end if;
 if attempt is null then insert into public.exam_attempts(user_id,exam_id) values(u,exam.id) returning id,started_at into attempt,started; end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'category',q.category,'prompt',q.prompt,'passage',case when q.category='reading' then q.passage else null end,'audio_script',case when q.category='listening' then q.passage else null end,
  'rubric',case when not q.is_objective then q.rubric else null end,
  'options',coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'option_text',o.option_text) order by o.order_index) from public.exam_question_options o where o.question_id=q.id),'[]'::jsonb)) order by q.order_index),'[]'::jsonb)
 into questions from public.exam_questions q where q.exam_id=exam.id;
 select coalesce(jsonb_agg(jsonb_build_object('question_id',r.question_id,'answer',r.answer)),'[]'::jsonb) into saved from public.exam_responses r where r.attempt_id=attempt;
 return jsonb_build_object('attempt_id',attempt,'exam_id',exam.id,'title',exam.title,'duration_seconds',exam.duration_seconds,'started_at',started,'resumed',resumed,'saved_answers',saved,'questions',questions);
end $$;

create or replace function public.submit_toefl_answer(p_attempt_id uuid,p_question_id uuid,p_answer text) returns void
language plpgsql security definer set search_path='' as $$
declare exam uuid; started timestamptz; duration integer;
begin
 perform 1 from public.profiles where id=auth.uid() for update;
 if not public.account_active() then raise exception 'Account access restricted'; end if;
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if exists(select 1 from public.profiles where id=auth.uid() and is_banned) then raise exception 'Account is suspended'; end if;
 select a.exam_id,a.started_at,s.duration_seconds into exam,started,duration from public.exam_attempts a join public.exam_sets s on s.id=a.exam_id where a.id=p_attempt_id and a.user_id=auth.uid() and a.status='in_progress' for update of a;
 if not found then raise exception 'Exam attempt is not active'; end if;
 if now()>started+duration*interval '1 second' then raise exception 'The exam time has ended'; end if;
 if not exists(select 1 from public.exam_questions where id=p_question_id and exam_id=exam) then raise exception 'Question does not belong to this exam'; end if;
 if length(trim(p_answer)) not between 1 and 4000 then raise exception 'Answer is required'; end if;
 if exists(select 1 from public.exam_questions where id=p_question_id and exam_id=exam and is_objective)
   and not exists(select 1 from public.exam_question_options where question_id=p_question_id and id::text=trim(p_answer))
 then raise exception 'Choose an answer for this question'; end if;
 insert into public.exam_responses(attempt_id,question_id,answer) values(p_attempt_id,p_question_id,trim(p_answer))
 on conflict(attempt_id,question_id) do update set answer=excluded.answer,is_correct=null,created_at=now();
end $$;

create or replace function public.finish_toefl_attempt(p_attempt_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); exam uuid; total integer; correct integer; score integer; bonus integer:=0; msg text; breakdown jsonb; review jsonb;
begin
 perform 1 from public.profiles where id=auth.uid() for update;
 if not public.account_active() then raise exception 'Account access restricted'; end if;
 if u is null then raise exception 'Sign in required'; end if;
 if exists(select 1 from public.profiles where id=u and is_banned) then raise exception 'Account is suspended'; end if;
 select exam_id into exam from public.exam_attempts where id=p_attempt_id and user_id=u and status='in_progress' for update;
 if not found then raise exception 'Exam attempt is not active'; end if;
 if exists(select 1 from public.exam_questions q where q.exam_id=exam and not exists(select 1 from public.exam_responses r where r.attempt_id=p_attempt_id and r.question_id=q.id))
    and now() < (select a.started_at+s.duration_seconds*interval '1 second' from public.exam_attempts a join public.exam_sets s on s.id=a.exam_id where a.id=p_attempt_id)
 then raise exception 'Answer each question before finishing'; end if;
 update public.exam_responses r set is_correct=case when q.is_objective then exists(select 1 from public.exam_question_options o where o.question_id=q.id and o.id::text=r.answer and o.is_correct) else null end
 from public.exam_questions q where r.question_id=q.id and q.exam_id=exam and r.attempt_id=p_attempt_id;
 select count(*) into total from public.exam_questions q where q.exam_id=exam and q.is_objective;
 select count(*) into correct from public.exam_questions q join public.exam_responses r on r.question_id=q.id and r.attempt_id=p_attempt_id where q.exam_id=exam and q.is_objective and r.is_correct=true;
 select coalesce(jsonb_agg(jsonb_build_object('category',s.category,'correct',s.correct,'total',s.total,'score_percentage',case when s.total=0 then null else floor(100.0*s.correct/s.total)::integer end) order by s.category),'[]'::jsonb)
 into breakdown from (select q.category,count(*) filter(where q.is_objective)::integer total,count(*) filter(where q.is_objective and r.is_correct=true)::integer correct
  from public.exam_questions q left join public.exam_responses r on r.question_id=q.id and r.attempt_id=p_attempt_id where q.exam_id=exam group by q.category) s;
 select coalesce(jsonb_agg(jsonb_build_object('category',q.category,'prompt',q.prompt,'is_correct',r.is_correct,
  'selected_answer',selected.option_text,'correct_answer',answer.option_text,'explanation',answer.explanation) order by q.order_index),'[]'::jsonb)
 into review from public.exam_questions q join public.exam_responses r on r.question_id=q.id and r.attempt_id=p_attempt_id
 left join public.exam_question_options selected on selected.id::text=r.answer
 left join lateral (select o.option_text,o.explanation from public.exam_question_options o where o.question_id=q.id and o.is_correct order by o.order_index limit 1) answer on true
 where q.exam_id=exam and q.is_objective;
 score:=case when total=0 then 0 else floor(100.0*correct/total)::integer end;
 update public.exam_attempts set status='completed',score_percentage=score,correct_answers=correct,total_questions=total,completed_at=now() where id=p_attempt_id;
 bonus:=private.grant_xp(u,10+floor(score*0.4)::integer,'toefl_exam',exam::text||':'||current_date::text,'Completed TOEFL practice simulation');
 insert into public.user_achievements(user_id,achievement_id) select u,id from public.achievements where slug='first-toefl' on conflict do nothing;
 if found then bonus:=bonus+private.grant_xp(u,50,'achievement','first-toefl','First TOEFL simulation achievement'); end if;
 msg:=case when score>=80 then 'A strong practice run. Review any missed items and keep building your range.' when score>=50 then 'A useful foundation. Revisit the questions you missed and practise one skill at a time.' else 'This first run gives you a baseline. Review the explanations, then try again after practice.' end;
 return jsonb_build_object('score_percentage',score,'correct_answers',correct,'total_questions',total,'skill_breakdown',breakdown,'review',review,'xp_awarded',bonus,'feedback',msg);
end $$;

create or replace function public.create_forum_thread(p_title text,p_body text) returns uuid language plpgsql security definer set search_path='' as $$
declare v uuid;
begin
 perform 1 from public.profiles where id=auth.uid() for update;
 if not public.account_active() then raise exception 'Account access restricted'; end if;
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if exists(select 1 from public.profiles where id=auth.uid() and is_banned) then raise exception 'Account is suspended'; end if;
 insert into public.forum_threads(user_id,title,body) values(auth.uid(),trim(p_title),trim(p_body)) returning id into v; return v;
end $$;

create or replace function public.create_forum_reply(p_thread_id uuid,p_body text) returns uuid language plpgsql security definer set search_path='' as $$
declare v uuid;
begin
 perform 1 from public.profiles where id=auth.uid() for update;
 if not public.account_active() then raise exception 'Account access restricted'; end if;
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if exists(select 1 from public.profiles where id=auth.uid() and is_banned) then raise exception 'Account is suspended'; end if;
 if not exists(select 1 from public.forum_threads where id=p_thread_id and status='published') then raise exception 'Thread not found'; end if;
 insert into public.forum_replies(thread_id,user_id,body) values(p_thread_id,auth.uid(),trim(p_body)) returning id into v;
 update public.forum_threads set reply_count=reply_count+1,updated_at=now() where id=p_thread_id; return v;
end $$;

create or replace function public.report_forum_content(p_content_type text,p_content_id uuid,p_reason text) returns uuid language plpgsql security definer set search_path='' as $$
declare v uuid;
begin
 perform 1 from public.profiles where id=auth.uid() for update;
 if not public.account_active() then raise exception 'Account access restricted'; end if;
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if p_content_type not in ('thread','reply') then raise exception 'Invalid report type'; end if;
 if (p_content_type='thread' and not exists(select 1 from public.forum_threads where id=p_content_id)) or (p_content_type='reply' and not exists(select 1 from public.forum_replies where id=p_content_id)) then raise exception 'Content not found'; end if;
 if p_reason is null or length(trim(p_reason)) not between 5 and 1000 then raise exception 'Provide a report reason of 5 to 1000 characters'; end if;
 select id into v from public.forum_reports where reporter_id=auth.uid() and content_type=p_content_type and content_id=p_content_id and status='open';
 if found then return v; end if;
 if (select count(*) from public.forum_reports where reporter_id=auth.uid() and created_at::date=current_date)>=10 then raise exception 'Daily reporting limit reached. Please wait before submitting another report'; end if;
 insert into public.forum_reports(reporter_id,content_type,content_id,reason) values(auth.uid(),p_content_type,p_content_id,trim(p_reason)) on conflict(reporter_id,content_type,content_id) where status='open' do nothing returning id into v;
 if v is null then select id into v from public.forum_reports where reporter_id=auth.uid() and content_type=p_content_type and content_id=p_content_id and status='open'; end if;
 return v;
end $$;

create function public.admin_moderate_user(p_user_id uuid,p_action text,p_reason text,p_until timestamptz default null) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'Administrator access required'; end if;
 if p_reason is null or length(trim(p_reason)) not between 5 and 1000 then raise exception 'A reason is required'; end if;
 perform 1 from public.profiles where id=p_user_id and role<>'admin' and id<>auth.uid() for update;
 if not found then raise exception 'Member cannot be moderated'; end if;
 if p_action='warn' then
 insert into public.user_warnings(user_id,moderator_id,reason) values(p_user_id,auth.uid(),trim(p_reason));
 elsif p_action='suspend' then
 if p_until is null or p_until<=now() or p_until>now()+interval '365 days' then raise exception 'Choose an end date within one year'; end if;
 update public.profiles set suspended_until=p_until where id=p_user_id;
 elsif p_action='ban' then update public.profiles set is_banned=true where id=p_user_id;
 elsif p_action='restore' then update public.profiles set is_banned=false,suspended_until=null where id=p_user_id;
 else raise exception 'Invalid moderation action'; end if;
 insert into public.moderation_history(actor_id,target_id,action,details) values(auth.uid(),p_user_id,p_action,jsonb_build_object('reason',trim(p_reason),'until',p_until));
end $$;
revoke all on function public.admin_moderate_user(uuid,text,text,timestamptz) from public,anon;
grant execute on function public.admin_moderate_user(uuid,text,text,timestamptz) to authenticated;
create function private.audit_moderation() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.moderation_history(actor_id,target_id,action,details) values(auth.uid(),new.id,TG_TABLE_NAME||':'||TG_OP,jsonb_build_object('before',to_jsonb(old),'after',to_jsonb(new)));
 return new;
end $$;
revoke all on function private.audit_moderation() from public,anon,authenticated;
create trigger reports_audit after update on public.forum_reports for each row execute function private.audit_moderation();
create trigger threads_audit after update of status on public.forum_threads for each row execute function private.audit_moderation();
create trigger replies_audit after update of status on public.forum_replies for each row execute function private.audit_moderation();
create trigger profile_access_audit after update of is_banned,role,suspended_until on public.profiles for each row execute function private.audit_moderation();
commit;
