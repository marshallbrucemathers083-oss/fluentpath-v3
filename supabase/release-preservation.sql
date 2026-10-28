-- Read-only fingerprints; compare during a quiet window BEFORE admin bootstrap/smoke writes.
-- Normalize the newly added nullable profile column so before/after schema shapes match.
with rows as (
 select 'profiles' as source,to_jsonb(p)-'suspended_until' as payload from public.profiles p
 union all select 'lesson_progress',to_jsonb(p) from public.lesson_progress p
 union all select 'exercise_attempts',to_jsonb(p) from public.exercise_attempts p
 union all select 'xp_transactions',to_jsonb(p) from public.xp_transactions p
 union all select 'user_achievements',to_jsonb(p) from public.user_achievements p
)
select source,count(*) as row_count,md5(string_agg(payload::text,E'\n' order by payload::text)) as preservation_digest
from rows group by source order by source;
