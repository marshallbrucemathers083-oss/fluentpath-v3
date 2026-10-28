-- Read-only checks to run in Supabase SQL Editor after applying all 3 migrations.

-- Expected tables, RLS state, and policy count. Every row should exist,
-- rls_enabled should be true, and policy_count should be greater than zero.
with expected(table_name) as (values
  ('profiles'),('lessons'),('lesson_sections'),('exercises'),('exercise_options'),
  ('lesson_progress'),('exercise_attempts'),('xp_transactions'),('achievements'),
  ('user_achievements'),('daily_quests'),('user_quests'),('exam_sets'),
  ('exam_questions'),('exam_question_options'),('exam_attempts'),('exam_responses'),
  ('forum_threads'),('forum_replies'),('forum_reports'),('user_warnings')
)
select e.table_name,
       coalesce(c.relrowsecurity, false) as rls_enabled,
       (select count(*) from pg_catalog.pg_policies p
        where p.schemaname = 'public' and p.tablename = e.table_name) as policy_count
from expected e
left join pg_catalog.pg_class c
  on c.relname = e.table_name and c.relnamespace = 'public'::regnamespace and c.relkind = 'r'
order by e.table_name;

-- Both allowlisted public views should exist.
select viewname
from pg_catalog.pg_views
where schemaname = 'public' and viewname in ('public_leaderboard','community_profiles')
order by viewname;

-- Every application RPC should exist and have the intended execute grants.
-- is_staff is intentionally callable by anon for RLS checks; all others are auth-only.
with expected(signature, anon_expected, authenticated_expected) as (values
  ('public.is_staff()', true, true),
  ('public.is_admin()', false, true),
  ('public.ensure_daily_quests()', false, true),
  ('public.get_lesson(text)', false, true),
  ('public.submit_exercise(uuid,uuid)', false, true),
  ('public.submit_written_response(uuid,text)', false, true),
  ('public.update_my_profile(text,text,public.cefr_level)', false, true),
  ('public.admin_list_users()', false, true),
  ('public.get_my_leaderboard_rank()', false, true),
  ('public.admin_set_user_ban(uuid,boolean)', false, true),
  ('public.admin_set_user_role(uuid,public.user_role)', false, true),
  ('public.start_toefl_attempt()', false, true),
  ('public.submit_toefl_answer(uuid,uuid,text)', false, true),
  ('public.finish_toefl_attempt(uuid)', false, true),
  ('public.create_forum_thread(text,text)', false, true),
  ('public.create_forum_reply(uuid,text)', false, true),
  ('public.report_forum_content(text,uuid,text)', false, true),
  ('public.moderate_forum_report(uuid,text)', false, true),
  ('public.moderate_forum_content(text,uuid,text)', false, true)
)
select e.signature,
       p.oid is not null as exists,
       coalesce(pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE'), false) as anon_can_execute,
       coalesce(pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE'), false) as authenticated_can_execute,
       coalesce(pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE'), false) = e.anon_expected
       and coalesce(pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE'), false) = e.authenticated_expected as grants_match
from expected e
left join pg_catalog.pg_proc p on p.oid = pg_catalog.to_regprocedure(e.signature)
order by e.signature;

-- Signup and lesson-publication triggers should both be enabled.
select t.tgname as trigger_name,
       c.relname as table_name,
       t.tgenabled = 'O' as enabled
from pg_catalog.pg_trigger t
join pg_catalog.pg_class c on c.oid = t.tgrelid
where not t.tgisinternal
  and ((c.relnamespace = 'auth'::regnamespace and t.tgname = 'on_auth_user_created')
       or (c.relnamespace = 'public'::regnamespace and t.tgname = 'lessons_require_complete_content'))
order by t.tgname;

-- Curriculum and exam seed totals. Expected: 12 lessons, 12 sections,
-- 12 exercises (9 objective, 3 response), 27 exercise options,
-- one published exam with 6 questions and 12 objective options.
select
  (select count(*) from public.lessons) as lessons,
  (select count(*) from public.lesson_sections) as lesson_sections,
  (select count(*) from public.exercises) as exercises,
  (select count(*) from public.exercises where exercise_type = 'short_response') as response_exercises,
  (select count(*) from public.exercise_options) as exercise_options,
  (select count(*) from public.exam_sets where is_published) as published_exams,
  (select count(*) from public.exam_questions) as exam_questions,
  (select count(*) from public.exam_question_options) as exam_question_options,
  (select count(*) from public.daily_quests) as daily_quests,
  (select count(*) from public.achievements) as achievements;

select cefr_level, count(*) as lesson_count
from public.lessons
group by cefr_level
order by cefr_level;
