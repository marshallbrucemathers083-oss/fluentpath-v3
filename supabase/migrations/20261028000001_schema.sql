-- FluentPath V2 core schema. Apply only after review in the Supabase SQL editor.
begin;
create extension if not exists pgcrypto with schema extensions;

do $$ begin create type public.cefr_level as enum ('A1','A2','B1','B2','C1','C2'); exception when duplicate_object then null; end $$;
do $$ begin create type public.skill_category as enum ('grammar','vocabulary','reading','listening','writing','speaking'); exception when duplicate_object then null; end $$;
do $$ begin create type public.user_role as enum ('student','moderator','admin'); exception when duplicate_object then null; end $$;
do $$ begin create type public.exercise_type as enum ('multiple_choice','fill_blank','reading_comprehension','listening','short_response'); exception when duplicate_object then null; end $$;
do $$ begin create type public.progress_status as enum ('not_started','in_progress','completed'); exception when duplicate_object then null; end $$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  full_name text not null default 'Learner' check (length(full_name) between 1 and 80),
  avatar_url text,
  role public.user_role not null default 'student',
  current_cefr_level public.cefr_level not null default 'A1',
  total_xp integer not null default 0 check (total_xp >= 0),
  streak_count integer not null default 0 check (streak_count >= 0),
  last_study_date date,
  bio text check (bio is null or length(bio) <= 280),
  is_banned boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists profiles_leaderboard_idx on public.profiles(total_xp desc, id);

create table if not exists public.lessons (
  id uuid primary key default gen_random_uuid(),
  title text not null check (length(title) between 2 and 120),
  slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  description text not null check (length(description) <= 500),
  cefr_level public.cefr_level not null,
  category public.skill_category not null,
  order_index integer not null default 0,
  xp_reward integer not null default 20 check (xp_reward between 1 and 200),
  estimated_minutes integer not null default 10 check (estimated_minutes between 1 and 180),
  is_published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists lessons_path_idx on public.lessons(cefr_level, category, order_index);

create table if not exists public.lesson_sections (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null references public.lessons(id) on delete cascade,
  title text not null,
  content text not null,
  section_type text not null default 'concept' check (section_type in ('concept','dialogue','rule','example','practice_tip')),
  order_index integer not null default 0,
  created_at timestamptz not null default now(),
  unique(lesson_id, order_index)
);

create table if not exists public.exercises (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null references public.lessons(id) on delete cascade,
  exercise_type public.exercise_type not null default 'multiple_choice',
  prompt text not null,
  passage text,
  audio_url text,
  rubric text,
  points integer not null default 10 check (points between 1 and 100),
  order_index integer not null default 0,
  created_at timestamptz not null default now(),
  unique(lesson_id, order_index)
);
create index if not exists exercises_lesson_idx on public.exercises(lesson_id, order_index);

-- Correctness and explanations are not readable through the public table API.
create table if not exists public.exercise_options (
  id uuid primary key default gen_random_uuid(),
  exercise_id uuid not null references public.exercises(id) on delete cascade,
  option_text text not null,
  is_correct boolean not null default false,
  explanation text not null default '',
  order_index integer not null default 0,
  unique(exercise_id, order_index)
);

create table if not exists public.lesson_progress (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  lesson_id uuid not null references public.lessons(id) on delete cascade,
  status public.progress_status not null default 'not_started',
  score_percentage integer check (score_percentage between 0 and 100),
  completed_at timestamptz,
  updated_at timestamptz not null default now(),
  unique(user_id, lesson_id)
);
create index if not exists progress_user_idx on public.lesson_progress(user_id, updated_at desc);

create table if not exists public.exercise_attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  exercise_id uuid not null references public.exercises(id) on delete cascade,
  submitted_answer text not null,
  is_correct boolean,
  points_earned integer not null default 0 check (points_earned >= 0),
  created_at timestamptz not null default now()
);
create index if not exists attempts_user_exercise_idx on public.exercise_attempts(user_id, exercise_id, created_at desc);

create table if not exists public.xp_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  amount integer not null check (amount between 1 and 1000),
  source_type text not null check (source_type in ('exercise','lesson_completion','achievement','daily_quest','toefl_exam','admin_adjustment')),
  source_id text,
  description text,
  created_at timestamptz not null default now(),
  unique(user_id, source_type, source_id)
);
create index if not exists xp_user_created_idx on public.xp_transactions(user_id, created_at desc);

create table if not exists public.achievements (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  title text not null,
  description text not null,
  icon text not null default '•',
  xp_reward integer not null default 0 check (xp_reward between 0 and 500),
  criteria_type text not null,
  criteria_threshold integer not null default 1 check (criteria_threshold > 0)
);
create table if not exists public.user_achievements (
  user_id uuid not null references public.profiles(id) on delete cascade,
  achievement_id uuid not null references public.achievements(id) on delete cascade,
  earned_at timestamptz not null default now(),
  primary key(user_id, achievement_id)
);

create table if not exists public.daily_quests (
  id uuid primary key default gen_random_uuid(),
  title text not null unique,
  description text not null,
  target_count integer not null check (target_count > 0),
  xp_reward integer not null check (xp_reward between 1 and 200),
  quest_type text not null check (quest_type in ('complete_exercises','earn_xp')),
  is_active boolean not null default true
);
create table if not exists public.user_quests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  quest_id uuid not null references public.daily_quests(id) on delete cascade,
  quest_date date not null default current_date,
  progress integer not null default 0 check (progress >= 0),
  is_completed boolean not null default false,
  completed_at timestamptz,
  unique(user_id, quest_id, quest_date)
);

create table if not exists public.exam_sets (
  id uuid primary key default gen_random_uuid(),
  title text not null unique,
  description text not null default '',
  cefr_level public.cefr_level not null default 'B1',
  duration_seconds integer not null default 1800 check (duration_seconds between 300 and 14400),
  is_published boolean not null default false,
  created_at timestamptz not null default now()
);
create table if not exists public.exam_questions (
  id uuid primary key default gen_random_uuid(),
  exam_id uuid not null references public.exam_sets(id) on delete cascade,
  category public.skill_category not null,
  prompt text not null,
  passage text,
  rubric text,
  is_objective boolean not null default true,
  points integer not null default 1 check (points between 1 and 100),
  order_index integer not null default 0,
  unique(exam_id, order_index)
);
create table if not exists public.exam_question_options (
  id uuid primary key default gen_random_uuid(),
  question_id uuid not null references public.exam_questions(id) on delete cascade,
  option_text text not null,
  is_correct boolean not null default false,
  explanation text not null default '',
  order_index integer not null default 0,
  unique(question_id, order_index)
);
create table if not exists public.exam_attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  exam_id uuid not null references public.exam_sets(id) on delete restrict,
  status text not null default 'in_progress' check (status in ('in_progress','completed','abandoned')),
  score_percentage integer check (score_percentage between 0 and 100),
  correct_answers integer,
  total_questions integer,
  started_at timestamptz not null default now(),
  completed_at timestamptz
);
create index if not exists exam_attempt_user_idx on public.exam_attempts(user_id, started_at desc);
create table if not exists public.exam_responses (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.exam_attempts(id) on delete cascade,
  question_id uuid not null references public.exam_questions(id) on delete cascade,
  answer text not null,
  is_correct boolean,
  created_at timestamptz not null default now(),
  unique(attempt_id, question_id)
);

create table if not exists public.forum_threads (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (length(title) between 4 and 120),
  body text not null check (length(body) between 10 and 3000),
  status text not null default 'published' check (status in ('published','hidden','removed')),
  reply_count integer not null default 0 check (reply_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists forum_threads_recent_idx on public.forum_threads(status, created_at desc);
create table if not exists public.forum_replies (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.forum_threads(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (length(body) between 2 and 2000),
  status text not null default 'published' check (status in ('published','hidden','removed')),
  created_at timestamptz not null default now()
);
create index if not exists forum_replies_thread_idx on public.forum_replies(thread_id, created_at);
create table if not exists public.forum_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  content_type text not null check (content_type in ('thread','reply')),
  content_id uuid not null,
  reason text not null check (length(reason) between 5 and 1000),
  status text not null default 'open' check (status in ('open','resolved','dismissed')),
  moderator_id uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);
create index if not exists forum_reports_status_idx on public.forum_reports(status, created_at);
create table if not exists public.user_warnings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  moderator_id uuid not null references public.profiles(id),
  reason text not null check (length(reason) between 5 and 1000),
  created_at timestamptz not null default now()
);

-- Public views expose only deliberate community information, never account email.
create or replace view public.public_leaderboard with (security_barrier = true) as
  select id, full_name, avatar_url, current_cefr_level, total_xp, streak_count
  from public.profiles where is_banned = false;
create or replace view public.community_profiles with (security_barrier = true) as
  select id, full_name, current_cefr_level, avatar_url from public.profiles where is_banned = false;

comment on table public.exercise_options is 'Answer keys are private; use get_lesson and submit_exercise.';
comment on table public.exam_question_options is 'Exam answer keys are private; use start_toefl_attempt and finish_toefl_attempt.';

-- Fail closed even if the next migration has not been run yet.
alter table public.profiles enable row level security;
alter table public.lessons enable row level security;
alter table public.lesson_sections enable row level security;
alter table public.exercises enable row level security;
alter table public.exercise_options enable row level security;
alter table public.lesson_progress enable row level security;
alter table public.exercise_attempts enable row level security;
alter table public.xp_transactions enable row level security;
alter table public.achievements enable row level security;
alter table public.user_achievements enable row level security;
alter table public.daily_quests enable row level security;
alter table public.user_quests enable row level security;
alter table public.exam_sets enable row level security;
alter table public.exam_questions enable row level security;
alter table public.exam_question_options enable row level security;
alter table public.exam_attempts enable row level security;
alter table public.exam_responses enable row level security;
alter table public.forum_threads enable row level security;
alter table public.forum_replies enable row level security;
alter table public.forum_reports enable row level security;
alter table public.user_warnings enable row level security;
commit;
