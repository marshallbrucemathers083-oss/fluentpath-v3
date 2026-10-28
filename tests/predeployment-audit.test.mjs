import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const read = name => readFile(new URL('../supabase/' + name, import.meta.url), 'utf8');
test('trusted bootstrap is audited without impersonation and cannot take signup metadata as authority', async () => {
  const sql = await read('migrations/20261028000004_submission_and_moderation.sql');
  assert.match(sql, /actor_id uuid references public.profiles/);
  assert.match(sql, /actor_database_role text not null default session_user/);
  assert.match(sql, /revoke all on public.moderation_history from public,anon,authenticated/);
  const bootstrap = await read('admin-bootstrap.sql');
  assert.match(bootstrap, /selected_account uuid := null/);
  assert.match(bootstrap, /email_confirmed_at is null/);
  assert.match(bootstrap, /where id=selected_account/);
  assert.doesNotMatch(bootstrap, /create function|raw_user_meta_data/);
});
test('content changes preserve attempted lessons and serialize against learner submissions', async () => {
  const content = await read('migrations/20261028000006_admin_content.sql');
  assert.match(content, /Create a new lesson version to preserve existing learning progress/);
  assert.match(content, /revoke insert,update on public.exercises/);
  const sql = await read('migrations/20261028000004_submission_and_moderation.sql');
  assert.match(sql, /public.lessons where id=lesson and is_published for share/);
  assert.match(sql, /public.exam_sets where id=exam.id and is_published for share/);
});
test('legacy restore delegates to the audited restore operation that clears temporary restrictions', async () => {
  const sql = await read('migrations/20261028000007_admin_workflows.sql');
  const fn = sql.slice(sql.indexOf('create or replace function public.admin_set_user_ban'), sql.indexOf('drop policy report_read'));
  assert.match(fn, /public.admin_moderate_user/);
  assert.match(fn, /then 'ban' else 'restore'/);
});
