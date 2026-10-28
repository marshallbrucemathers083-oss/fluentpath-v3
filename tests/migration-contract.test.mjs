import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const read = name => readFile(new URL('../supabase/migrations/' + name, import.meta.url), 'utf8');
test('expanded curriculum covers every level and skill without overwriting progress', async () => {
  const sql = await read('20261028000005_scenario_curriculum.sql');
  for (const level of ['a1','a2','b1','b2','c1','c2']) {
    for (const skill of ['grammar','vocabulary','reading','listening','writing','speaking']) assert.ok(sql.includes(`${level}-${skill}-scenario-workshop`));
  }
  assert.doesNotMatch(sql, /delete from|truncate|update public.lesson_progress/i);
  assert.match(sql, /Unofficial TOEFL-style/);
});
test('moderation checks access and records actions; content RPC enforces admin and answer validity', async () => {
  const sql = await read('20261028000004_submission_and_moderation.sql');
  assert.match(sql, /for update/);
  assert.match(sql, /Account access restricted/);
  assert.match(sql, /reporter_id=auth.uid\(\)/);
  assert.match(sql, /create trigger reports_audit/);
  const admin = await read('20261028000006_admin_content.sql');
  assert.match(admin, /if not public.is_admin\(\)/);
  assert.match(admin, /correct_count<>1/);
  assert.match(admin, /status='in_progress'/);
});

test('new admin workflows validate publishing, preserve attempted exams, and close direct key writes', async () => {
  const sql = await read('20261028000007_admin_workflows.sql');
  for (const name of ['admin_platform_stats','admin_create_practice','admin_set_practice_status','admin_report_context']) {
    const start = sql.indexOf(`create function public.${name}`);
    const end = sql.indexOf('end $$;', start);
    assert.match(sql.slice(start,end), /if not public.is_admin\(\)/);
  }
  assert.match(sql, /revoke insert,update on public.exercises,public.exercise_options,public.exam_questions,public.exam_question_options from authenticated/);
  assert.match(sql, /to_jsonb\(r\)-'reporter_id'/);
  assert.match(sql, /Create a new set instead of changing an attempted set/);
  assert.match(sql, /Restore an archived lesson before publishing/);
});
