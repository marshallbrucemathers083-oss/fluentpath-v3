-- Authorization and trusted operations. Answer keys and scores stay in PostgreSQL.
begin;
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
revoke create on schema public from public, anon, authenticated;

create function public.handle_new_user() returns trigger language plpgsql security definer set search_path='' as $$
begin
  insert into public.profiles(id,email,full_name) values(new.id,coalesce(new.email,''),coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'),''),'Learner'))
  on conflict(id) do update set email=excluded.email;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create function public.is_staff() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles where id=auth.uid() and role in ('admin','moderator') and not is_banned)
$$;
create function public.is_admin() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles where id=auth.uid() and role='admin' and not is_banned)
$$;

create function private.grant_xp(p_user uuid,p_amount integer,p_source text,p_source_id text,p_note text)
returns integer language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_bonus integer:=0;
begin
 if p_amount<1 or p_amount>500 then return 0; end if;
 insert into public.xp_transactions(user_id,amount,source_type,source_id,description)
 values(p_user,p_amount,p_source,p_source_id,p_note)
 on conflict(user_id,source_type,source_id) do nothing returning id into v_id;
 if v_id is null then return 0; end if;
 update public.profiles set total_xp=total_xp+p_amount,
  streak_count=case when last_study_date=current_date then streak_count when last_study_date=current_date-1 then streak_count+1 else 1 end,
  last_study_date=current_date,updated_at=now() where id=p_user;
 if exists(select 1 from public.profiles where id=p_user and streak_count>=7) then
  insert into public.user_achievements(user_id,achievement_id) select p_user,id from public.achievements where slug='seven-day-streak' on conflict do nothing;
  if found then v_bonus:=private.grant_xp(p_user,100,'achievement','seven-day-streak','A week of practice achievement'); end if;
 end if;
 return p_amount+v_bonus;
end $$;

create function private.advance_quests(p_user uuid,p_exercises integer,p_xp integer)
returns integer language plpgsql security definer set search_path='' as $$
declare q record; v_delta integer; v_bonus integer:=0;
begin
 for q in select uq.id,uq.quest_id,uq.progress,dq.target_count,dq.xp_reward,dq.quest_type
  from public.user_quests uq join public.daily_quests dq on dq.id=uq.quest_id
  where uq.user_id=p_user and uq.quest_date=current_date and not uq.is_completed
 loop
  v_delta:=case when q.quest_type='complete_exercises' then p_exercises else p_xp end;
  if v_delta>0 then
   update public.user_quests set progress=least(q.target_count,progress+v_delta),
    is_completed=(progress+v_delta)>=q.target_count,
    completed_at=case when progress+v_delta>=q.target_count then now() else null end where id=q.id;
   if q.progress+v_delta>=q.target_count then
    v_bonus:=v_bonus+private.grant_xp(p_user,q.xp_reward,'daily_quest',q.quest_id::text||':'||current_date::text,'Daily quest completed');
   end if;
  end if;
 end loop;
 return v_bonus;
end $$;

create function public.ensure_daily_quests() returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 insert into public.user_quests(user_id,quest_id,quest_date)
 select auth.uid(),id,current_date from public.daily_quests where is_active
 on conflict(user_id,quest_id,quest_date) do nothing;
end $$;

create function public.get_lesson(p_slug text) returns jsonb language plpgsql security definer set search_path='' as $$
declare l public.lessons%rowtype; v_sections jsonb; v_exercises jsonb;
begin
 select * into l from public.lessons where slug=p_slug and is_published;
 if not found then raise exception 'Lesson not found'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'title',s.title,'content',s.content,'section_type',s.section_type) order by s.order_index),'[]'::jsonb)
 into v_sections from public.lesson_sections s where s.lesson_id=l.id;
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',e.id,'exercise_type',e.exercise_type,'prompt',e.prompt,
  'passage',case when l.category='reading' then e.passage else null end,
  'audio_script',case when l.category='listening' then e.passage else null end,
  'rubric',case when e.exercise_type='short_response' then e.rubric else null end,
  'points',e.points,
  'options',coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'option_text',o.option_text) order by o.order_index) from public.exercise_options o where o.exercise_id=e.id),'[]'::jsonb)
 ) order by e.order_index),'[]'::jsonb)
 into v_exercises from public.exercises e where e.lesson_id=l.id;
 return jsonb_build_object('lesson',to_jsonb(l),'sections',v_sections,'exercises',v_exercises);
end $$;

create function public.submit_exercise(p_exercise_id uuid,p_option_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); lesson uuid; correct boolean; feedback text; points integer; earned integer:=0; done_xp integer:=0; quest_xp integer:=0; completed boolean:=false; score integer; first_today boolean;
begin
 if u is null then raise exception 'Sign in required'; end if;
 if exists(select 1 from public.profiles where id=u and is_banned) then raise exception 'Account is suspended'; end if;
 select e.lesson_id,e.points into lesson,points from public.exercises e join public.lessons l on l.id=e.lesson_id
  where e.id=p_exercise_id and l.is_published and e.exercise_type<>'short_response';
 if not found then raise exception 'Exercise not found'; end if;
 select o.is_correct,o.explanation into correct,feedback from public.exercise_options o where o.id=p_option_id and o.exercise_id=p_exercise_id;
 if not found then raise exception 'Answer is not part of this exercise'; end if;
 select not exists(select 1 from public.exercise_attempts a where a.user_id=u and a.exercise_id=p_exercise_id and a.is_correct=true and a.created_at::date=current_date) into first_today;
 insert into public.exercise_attempts(user_id,exercise_id,submitted_answer,is_correct,points_earned)
 values(u,p_exercise_id,p_option_id::text,correct,case when correct then points else 0 end);
 insert into public.lesson_progress(user_id,lesson_id,status) values(u,lesson,'in_progress')
 on conflict(user_id,lesson_id) do update set status=case when public.lesson_progress.status='completed' then 'completed' else 'in_progress' end,updated_at=now();
 if correct then earned:=private.grant_xp(u,least(points,30),'exercise',p_exercise_id::text,'Correct exercise answer'); end if;
 if not exists(select 1 from public.exercises e where e.lesson_id=lesson and not exists(
  select 1 from public.exercise_attempts a where a.user_id=u and a.exercise_id=e.id and (a.is_correct=true or (a.is_correct is null and e.exercise_type='short_response'))))
 then
  select coalesce(floor(100.0*count(*) filter(where exists(select 1 from public.exercise_attempts a where a.user_id=u and a.exercise_id=e.id and (a.is_correct=true or a.is_correct is null)))/nullif(count(*),0)),100)::integer
  into score from public.exercises e where e.lesson_id=lesson;
  update public.lesson_progress set status='completed',score_percentage=score,completed_at=coalesce(completed_at,now()),updated_at=now() where user_id=u and lesson_id=lesson;
  done_xp:=private.grant_xp(u,20,'lesson_completion',lesson::text,'Lesson completed');
  insert into public.user_achievements(user_id,achievement_id) select u,id from public.achievements where slug='first-lesson' on conflict do nothing;
  if found then earned:=earned+private.grant_xp(u,50,'achievement','first-lesson','First lesson achievement'); end if;
  if score=100 then
   insert into public.user_achievements(user_id,achievement_id) select u,id from public.achievements where slug='perfect-practice' on conflict do nothing;
   if found then earned:=earned+private.grant_xp(u,40,'achievement','perfect-practice','Perfect practice achievement'); end if;
  end if;
  completed:=true;
 end if;
 quest_xp:=private.advance_quests(u,case when correct and first_today then 1 else 0 end,earned+done_xp);
 return jsonb_build_object('correct',correct,'feedback',coalesce(feedback,''),'xp_awarded',earned+done_xp+quest_xp,'lesson_completed',completed);
end $$;

create function public.submit_written_response(p_exercise_id uuid,p_response text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); lesson uuid; guidance text; earned integer; done_xp integer:=0; quest_xp integer:=0; completed boolean:=false; first_today boolean;
begin
 if u is null then raise exception 'Sign in required'; end if;
 if exists(select 1 from public.profiles where id=u and is_banned) then raise exception 'Account is suspended'; end if;
 if length(trim(p_response))<20 or length(p_response)>4000 then raise exception 'Write at least 20 characters and no more than 4000'; end if;
 select e.lesson_id,e.rubric into lesson,guidance from public.exercises e join public.lessons l on l.id=e.lesson_id
  where e.id=p_exercise_id and e.exercise_type='short_response' and l.is_published;
 if not found then raise exception 'Writing exercise not found'; end if;
 select not exists(select 1 from public.exercise_attempts a where a.user_id=u and a.exercise_id=p_exercise_id and a.is_correct is null and a.created_at::date=current_date) into first_today;
 insert into public.exercise_attempts(user_id,exercise_id,submitted_answer,is_correct,points_earned) values(u,p_exercise_id,trim(p_response),null,5);
 insert into public.lesson_progress(user_id,lesson_id,status) values(u,lesson,'in_progress') on conflict(user_id,lesson_id) do update set updated_at=now();
 earned:=private.grant_xp(u,5,'exercise',p_exercise_id::text,'Writing response submitted');
 if not exists(select 1 from public.exercises e where e.lesson_id=lesson and not exists(select 1 from public.exercise_attempts a where a.user_id=u and a.exercise_id=e.id and (a.is_correct=true or a.is_correct is null))) then
  update public.lesson_progress set status='completed',score_percentage=null,completed_at=coalesce(completed_at,now()),updated_at=now() where user_id=u and lesson_id=lesson;
  done_xp:=private.grant_xp(u,20,'lesson_completion',lesson::text,'Lesson completed'); completed:=true;
  insert into public.user_achievements(user_id,achievement_id) select u,id from public.achievements where slug='first-lesson' on conflict do nothing;
  if found then earned:=earned+private.grant_xp(u,50,'achievement','first-lesson','First lesson achievement'); end if;
 end if;
 quest_xp:=private.advance_quests(u,case when first_today then 1 else 0 end,earned+done_xp);
 return jsonb_build_object('feedback',coalesce(guidance,'Review your response for clarity, accurate language, and a clear structure.'),'xp_awarded',earned+done_xp+quest_xp,'lesson_completed',completed);
end $$;

create function public.update_my_profile(p_full_name text,p_bio text,p_level public.cefr_level)
returns public.profiles language plpgsql security definer set search_path='' as $$
declare p public.profiles%rowtype;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if length(trim(p_full_name)) not between 2 and 80 or length(coalesce(p_bio,''))>280 then raise exception 'Check the name and bio length'; end if;
 update public.profiles set full_name=trim(p_full_name),bio=nullif(trim(p_bio),''),current_cefr_level=p_level,updated_at=now()
  where id=auth.uid() returning * into p;
 return p;
end $$;

create function public.admin_list_users()
returns table(id uuid,email text,full_name text,role public.user_role,is_banned boolean,total_xp integer)
language plpgsql stable security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'Administrator access required'; end if;
 return query select p.id,p.email,p.full_name,p.role,p.is_banned,p.total_xp from public.profiles p order by p.created_at desc limit 500;
end $$;
create function public.get_my_leaderboard_rank() returns integer language sql stable security definer set search_path='' as $$
 select case when me.id is null or me.is_banned then null else 1+(select count(*)::integer from public.profiles other where not other.is_banned and (other.total_xp>me.total_xp or (other.total_xp=me.total_xp and other.id<me.id))) end
 from public.profiles me where me.id=auth.uid()
$$;
create function public.admin_set_user_ban(p_user_id uuid,p_is_banned boolean) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'Administrator access required'; end if;
 if p_user_id=auth.uid() then raise exception 'You cannot suspend your own account'; end if;
 update public.profiles set is_banned=p_is_banned,updated_at=now() where id=p_user_id and role<>'admin';
 if not found then raise exception 'Member not found or cannot be suspended'; end if;
end $$;
create function public.admin_set_user_role(p_user_id uuid,p_role public.user_role) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'Administrator access required'; end if;
 if p_user_id=auth.uid() then raise exception 'You cannot change your own role'; end if;
 update public.profiles set role=p_role,updated_at=now() where id=p_user_id and role<>'admin';
 if not found then raise exception 'Member not found or cannot change this role'; end if;
end $$;

create function public.start_toefl_attempt() returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); exam public.exam_sets%rowtype; attempt uuid; started timestamptz; questions jsonb; saved jsonb; resumed boolean:=false;
begin
 if u is null then raise exception 'Sign in required'; end if;
 if exists(select 1 from public.profiles where id=u and is_banned) then raise exception 'Account is suspended'; end if;
 perform 1 from public.profiles where id=u for update;
 select * into exam from public.exam_sets where is_published order by created_at limit 1;
 if not found then raise exception 'No exam has been published yet'; end if;
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
create function public.submit_toefl_answer(p_attempt_id uuid,p_question_id uuid,p_answer text) returns void
language plpgsql security definer set search_path='' as $$
declare exam uuid; started timestamptz; duration integer;
begin
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
create function public.finish_toefl_attempt(p_attempt_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); exam uuid; total integer; correct integer; score integer; bonus integer:=0; msg text; breakdown jsonb; review jsonb;
begin
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

create function public.create_forum_thread(p_title text,p_body text) returns uuid language plpgsql security definer set search_path='' as $$
declare v uuid;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if exists(select 1 from public.profiles where id=auth.uid() and is_banned) then raise exception 'Account is suspended'; end if;
 insert into public.forum_threads(user_id,title,body) values(auth.uid(),trim(p_title),trim(p_body)) returning id into v; return v;
end $$;
create function public.create_forum_reply(p_thread_id uuid,p_body text) returns uuid language plpgsql security definer set search_path='' as $$
declare v uuid;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if exists(select 1 from public.profiles where id=auth.uid() and is_banned) then raise exception 'Account is suspended'; end if;
 if not exists(select 1 from public.forum_threads where id=p_thread_id and status='published') then raise exception 'Thread not found'; end if;
 insert into public.forum_replies(thread_id,user_id,body) values(p_thread_id,auth.uid(),trim(p_body)) returning id into v;
 update public.forum_threads set reply_count=reply_count+1,updated_at=now() where id=p_thread_id; return v;
end $$;
create function public.report_forum_content(p_content_type text,p_content_id uuid,p_reason text) returns uuid language plpgsql security definer set search_path='' as $$
declare v uuid;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if p_content_type not in ('thread','reply') then raise exception 'Invalid report type'; end if;
 if (p_content_type='thread' and not exists(select 1 from public.forum_threads where id=p_content_id)) or (p_content_type='reply' and not exists(select 1 from public.forum_replies where id=p_content_id)) then raise exception 'Content not found'; end if;
 insert into public.forum_reports(reporter_id,content_type,content_id,reason) values(auth.uid(),p_content_type,p_content_id,trim(p_reason)) returning id into v; return v;
end $$;
create function public.moderate_forum_report(p_report_id uuid,p_decision text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.is_staff() then raise exception 'Moderator access required'; end if;
 if p_decision not in ('resolve','dismiss') then raise exception 'Invalid decision'; end if;
 update public.forum_reports set status=case when p_decision='resolve' then 'resolved' else 'dismissed' end,moderator_id=auth.uid(),resolved_at=now() where id=p_report_id and status='open';
 if not found then raise exception 'Open report not found'; end if;
end $$;
create function public.moderate_forum_content(p_content_type text,p_content_id uuid,p_status text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not public.is_staff() then raise exception 'Moderator access required'; end if;
 if p_status not in ('published','hidden','removed') then raise exception 'Invalid status'; end if;
 if p_content_type='thread' then update public.forum_threads set status=p_status,updated_at=now() where id=p_content_id;
 elsif p_content_type='reply' then update public.forum_replies set status=p_status where id=p_content_id;
 else raise exception 'Invalid content type'; end if;
 if not found then raise exception 'Content not found'; end if;
end $$;

-- Turn RLS on for every table that has client access.
do $$ declare t text; begin
 foreach t in array array['profiles','lessons','lesson_sections','exercises','exercise_options','lesson_progress','exercise_attempts','xp_transactions','achievements','user_achievements','daily_quests','user_quests','exam_sets','exam_questions','exam_question_options','exam_attempts','exam_responses','forum_threads','forum_replies','forum_reports','user_warnings']
 loop execute format('alter table public.%I enable row level security',t); end loop;
end $$;

create policy profile_self_read on public.profiles for select to authenticated using(id=auth.uid());
create policy lessons_read on public.lessons for select to anon,authenticated using(is_published or public.is_staff());
create policy lessons_staff_insert on public.lessons for insert to authenticated with check(public.is_staff());
create policy lessons_staff_update on public.lessons for update to authenticated using(public.is_staff()) with check(public.is_staff());
create policy sections_read on public.lesson_sections for select to anon,authenticated using(exists(select 1 from public.lessons l where l.id=lesson_id and (l.is_published or public.is_staff())));
create policy sections_staff_manage on public.lesson_sections for all to authenticated using(public.is_staff()) with check(public.is_staff());
create policy exercises_read on public.exercises for select to anon,authenticated using(exists(select 1 from public.lessons l where l.id=lesson_id and (l.is_published or public.is_staff())));
create policy exercises_staff_manage on public.exercises for all to authenticated using(public.is_staff()) with check(public.is_staff());
create policy options_staff_manage on public.exercise_options for all to authenticated using(public.is_staff()) with check(public.is_staff());
create policy progress_self_read on public.lesson_progress for select to authenticated using(user_id=auth.uid());
create policy attempts_self_read on public.exercise_attempts for select to authenticated using(user_id=auth.uid());
create policy xp_self_read on public.xp_transactions for select to authenticated using(user_id=auth.uid());
create policy achievement_read on public.achievements for select to anon,authenticated using(true);
create policy user_achievement_read on public.user_achievements for select to authenticated using(user_id=auth.uid());
create policy quest_read on public.daily_quests for select to authenticated using(is_active);
create policy user_quest_read on public.user_quests for select to authenticated using(user_id=auth.uid());
create policy exam_set_read on public.exam_sets for select to authenticated using(is_published);
create policy exam_question_staff_read on public.exam_questions for select to authenticated using(public.is_staff());
create policy exam_option_staff_manage on public.exam_question_options for all to authenticated using(public.is_staff()) with check(public.is_staff());
create policy exam_attempt_read on public.exam_attempts for select to authenticated using(user_id=auth.uid());
create policy exam_response_read on public.exam_responses for select to authenticated using(exists(select 1 from public.exam_attempts a where a.id=attempt_id and a.user_id=auth.uid()));
create policy thread_read on public.forum_threads for select to authenticated using(status='published' or user_id=auth.uid() or public.is_staff());
create policy reply_read on public.forum_replies for select to authenticated using((status='published' and exists(select 1 from public.forum_threads t where t.id=thread_id and t.status='published')) or user_id=auth.uid() or public.is_staff());
create policy report_read on public.forum_reports for select to authenticated using(public.is_staff());
create policy warning_read on public.user_warnings for select to authenticated using(user_id=auth.uid() or public.is_staff());

create function private.validate_lesson_publish() returns trigger
language plpgsql security definer set search_path='' as $$
declare e record; n integer; c integer;
begin
 if new.is_published then
  if not exists(select 1 from public.lesson_sections where lesson_id=new.id) then raise exception 'Add at least one lesson note before publishing'; end if;
  if not exists(select 1 from public.exercises where lesson_id=new.id) then raise exception 'Add at least one exercise before publishing'; end if;
  for e in select id,exercise_type,rubric from public.exercises where lesson_id=new.id loop
   if e.exercise_type='short_response' then
    if length(trim(coalesce(e.rubric,'')))<10 then raise exception 'Add useful feedback guidance to each writing exercise'; end if;
   else
    select count(*),count(*) filter(where is_correct) into n,c from public.exercise_options where exercise_id=e.id;
    if n<2 or c<>1 then raise exception 'Each objective exercise needs at least two choices and exactly one correct answer'; end if;
   end if;
  end loop;
 end if;
 return new;
end $$;
create trigger lessons_require_complete_content before insert or update of is_published on public.lessons
for each row execute function private.validate_lesson_publish();

-- Revoke broad defaults, then add the smallest grants the frontend needs.
revoke all on all tables in schema public from anon,authenticated;
grant usage on schema public to anon,authenticated;
grant select on public.lessons,public.lesson_sections,public.exercises,public.achievements to anon,authenticated;
grant select on public.profiles,public.lesson_progress,public.exercise_attempts,public.xp_transactions,public.user_achievements,public.daily_quests,public.user_quests,public.exam_sets,public.exam_attempts,public.exam_responses,public.forum_threads,public.forum_replies,public.forum_reports,public.user_warnings to authenticated;
grant select on public.public_leaderboard,public.community_profiles to anon,authenticated;
grant select,insert,update on public.lessons,public.lesson_sections,public.exercises,public.exercise_options,public.exam_questions,public.exam_question_options to authenticated;

-- These tables contain keys, but RLS permits only staff direct access. Student RPCs return sanitized data.
revoke all on public.exercise_options,public.exam_questions,public.exam_question_options from anon,authenticated;
grant select,insert,update on public.exercise_options,public.exam_questions,public.exam_question_options to authenticated;

revoke all on function private.grant_xp(uuid,integer,text,text,text) from public,anon,authenticated;
revoke all on function private.advance_quests(uuid,integer,integer) from public,anon,authenticated;
revoke all on function private.validate_lesson_publish() from public,anon,authenticated;
revoke all on function public.handle_new_user() from public,anon,authenticated;
revoke all on function public.is_staff() from public,anon,authenticated;
revoke all on function public.is_admin() from public,anon,authenticated;
revoke all on function public.ensure_daily_quests() from public,anon;
revoke all on function public.get_lesson(text) from public,anon;
revoke all on function public.submit_exercise(uuid,uuid) from public,anon;
revoke all on function public.submit_written_response(uuid,text) from public,anon;
revoke all on function public.update_my_profile(text,text,public.cefr_level) from public,anon;
revoke all on function public.admin_list_users() from public,anon;
revoke all on function public.get_my_leaderboard_rank() from public,anon;
revoke all on function public.admin_set_user_ban(uuid,boolean) from public,anon;
revoke all on function public.admin_set_user_role(uuid,public.user_role) from public,anon;
revoke all on function public.start_toefl_attempt() from public,anon;
revoke all on function public.submit_toefl_answer(uuid,uuid,text) from public,anon;
revoke all on function public.finish_toefl_attempt(uuid) from public,anon;
revoke all on function public.create_forum_thread(text,text) from public,anon;
revoke all on function public.create_forum_reply(uuid,text) from public,anon;
revoke all on function public.report_forum_content(text,uuid,text) from public,anon;
revoke all on function public.moderate_forum_report(uuid,text) from public,anon;
revoke all on function public.moderate_forum_content(text,uuid,text) from public,anon;
grant execute on function public.is_staff(),public.is_admin(),public.ensure_daily_quests(),public.get_lesson(text),
 public.submit_exercise(uuid,uuid),public.submit_written_response(uuid,text),public.update_my_profile(text,text,public.cefr_level),
 public.admin_list_users(),public.get_my_leaderboard_rank(),public.admin_set_user_ban(uuid,boolean),public.admin_set_user_role(uuid,public.user_role),
 public.start_toefl_attempt(),public.submit_toefl_answer(uuid,uuid,text),public.finish_toefl_attempt(uuid),
 public.create_forum_thread(text,text),public.create_forum_reply(uuid,text),public.report_forum_content(text,uuid,text),
 public.moderate_forum_report(uuid,text),public.moderate_forum_content(text,uuid,text) to authenticated;
-- The helper returns false to anonymous visitors and is needed by public content RLS policies.
grant execute on function public.is_staff() to anon;
commit;

