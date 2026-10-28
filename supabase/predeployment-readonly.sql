-- Read-only preflight/snapshot. Run as a trusted operator; retain results before/after.
select version,name from supabase_migrations.schema_migrations order by version;
select reporter_id,content_type,content_id,count(*) as duplicate_count
from public.forum_reports where status='open' group by 1,2,3 having count(*)>1;
select slug from public.lessons where slug ~ '^(a1|a2|b1|b2|c1|c2)-(grammar|vocabulary|reading|listening|writing|speaking)-scenario-workshop$';
select id,title from public.exam_sets where title='Academic evidence and decisions';
select role,count(*) from public.profiles group by role;
select 'profiles' as table_name,count(*) as rows,coalesce(sum(total_xp),0) as total_xp from public.profiles
union all select 'lesson_progress',count(*),0 from public.lesson_progress
union all select 'exercise_attempts',count(*),0 from public.exercise_attempts
union all select 'xp_transactions',count(*),coalesce(sum(amount),0) from public.xp_transactions
union all select 'user_achievements',count(*),0 from public.user_achievements;
select c.relname,c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relkind='r' order by c.relname;
select tablename,policyname,roles,cmd,qual,with_check from pg_policies where schemaname='public' order by tablename,policyname;
select table_name,grantee,privilege_type from information_schema.table_privileges
where table_schema='public' and grantee in ('PUBLIC','anon','authenticated') order by table_name,grantee,privilege_type;
