import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const read = path => readFile(new URL(path, import.meta.url), 'utf8');

test('browser configuration uses only a project URL and publishable key', async () => {
  const config = await read('../js/config.js');
  assert.match(config, /https:\/\/grlwwmkjwhbxsnnfrovv\.supabase\.co/);
  assert.match(config, /sb_publishable_/);
  assert.doesNotMatch(config, /service_role|sb_secret_/i);
});

test('learner answer RPCs do not return answer-key columns', async () => {
  const sql = await read('../supabase/migrations/20261028000002_security_and_rpc.sql');
  const lessonRpc = sql.slice(sql.indexOf('create function public.get_lesson'), sql.indexOf('create function public.submit_exercise'));
  const examRpc = sql.slice(sql.indexOf('create function public.start_toefl_attempt'), sql.indexOf('create function public.submit_toefl_answer'));
  assert.match(lessonRpc, /jsonb_build_object\('id',o\.id,'option_text',o\.option_text\)/);
  assert.doesNotMatch(lessonRpc, /o\.is_correct|o\.explanation/);
  assert.match(examRpc, /jsonb_build_object\('id',o\.id,'option_text',o\.option_text\)/);
  assert.doesNotMatch(examRpc, /o\.is_correct|o\.explanation/);
});

test('the schema migration enables RLS for every application table', async () => {
  const schema = await read('../supabase/migrations/20261028000001_schema.sql');
  const security = await read('../supabase/migrations/20261028000002_security_and_rpc.sql');
  const tables = [...schema.matchAll(/create table if not exists public\.(\w+)/g)].map(match => match[1]);
  assert.equal(tables.length, 21);
  const enabled = security.match(/foreach t in array array\[([\s\S]*?)\]\s*loop/i)?.[1] || '';
  for (const table of tables) assert.ok(enabled.includes(`'${table}'`), `${table} is missing RLS`);
});

test('client cannot write progress, scores, profile roles, or XP directly', async () => {
  const security = await read('../supabase/migrations/20261028000002_security_and_rpc.sql');
  assert.match(security, /grant select on public\.profiles,public\.lesson_progress/);
  assert.doesNotMatch(security, /grant\s+(?:all|insert|update|delete)[^;]*public\.(?:profiles|lesson_progress|xp_transactions|exam_attempts)/i);
  assert.match(security, /revoke all on function public\.submit_exercise\(uuid,uuid\) from public,anon/);
  assert.match(security, /revoke all on function private\.grant_xp/);
  assert.match(security, /public\.start_toefl_attempt\(\),public\.submit_toefl_answer\(uuid,uuid,text\),public\.finish_toefl_attempt\(uuid\)[\s\S]*?to authenticated/);
});

test('definer functions pin an empty search path and public is not writable by clients', async () => {
  const security = await read('../supabase/migrations/20261028000002_security_and_rpc.sql');
  assert.match(security, /revoke create on schema public from public, anon, authenticated/i);
  const paths = [...security.matchAll(/security definer set search_path=([^\s]+) as \$\$/gi)].map(match => match[1]);
  assert.ok(paths.length >= 15, 'expected all privileged functions to pin their search path');
  assert.ok(paths.every(path => path === "''"), `unsafe function search_path: ${paths.filter(path => path !== "''").join(', ')}`);
});

test('TOEFL objective answers must belong to the submitted question', async () => {
  const security = await read('../supabase/migrations/20261028000002_security_and_rpc.sql');
  assert.match(security, /question_id=p_question_id and id::text=trim\(p_answer\)/);
  assert.match(security, /for update of a/);
});

test('written lesson responses can submit without an objective choice', async () => {
  const app = await read('../js/app.js');
  assert.match(app, /if \(!response && !selected\) return;/);
  assert.match(app, /submit_written_response', \{ p_exercise_id: card\.dataset\.exercise, p_response: response\.value\.trim\(\) \}/);
});

test('auth feedback uses one visible live region per page', async () => {
  const auth = await read('../js/auth.js');
  assert.match(auth, /if \(notice\) \{[\s\S]*?\} else if \(status\)/);
});

test('each migration is atomic and the base schema fails closed', async () => {
  const schema = await read('../supabase/migrations/20261028000001_schema.sql');
  const security = await read('../supabase/migrations/20261028000002_security_and_rpc.sql');
  const seed = await read('../supabase/migrations/20261028000003_seed_curriculum.sql');
  for (const sql of [schema, security, seed]) {
    assert.match(sql.trimStart(), /^--[^\n]*\n(?:begin;)/i);
    assert.match(sql.trimEnd(), /commit;$/i);
  }
  assert.match(schema, /alter table public\.profiles enable row level security/i);
  assert.match(schema, /alter table public\.exam_responses enable row level security/i);
});
