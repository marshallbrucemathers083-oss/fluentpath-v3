import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile,mkdtemp,rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { prepareHotfix } from '../scripts/prepare-hotfix.mjs';
const read = file=>readFile(new URL('../'+file,import.meta.url),'utf8');
const broken="case when public.lesson_progress.status='completed' then 'completed' else 'in_progress' end";
const fixed="case when public.lesson_progress.status='completed' then 'completed'::public.progress_status else 'in_progress'::public.progress_status end";
test('standalone hotfix patches only the exact enum CASE and preserves the live function definition',async()=>{
 const sql=await read('supabase/migrations/20261028115000_progress_status_enum_hotfix.sql');
 assert.ok(sql.includes(broken)); assert.ok(sql.includes(fixed));
 assert.match(sql,/pg_get_functiondef\('public.submit_exercise\(uuid,uuid\)'::regprocedure\)/);
 assert.match(sql,/execute replace\(definition,broken,fixed\)/);
 assert.match(sql,/Unexpected submit_exercise definition/);
 assert.doesNotMatch(sql,/suspended_until|archived_at|update public\.|delete from|alter type|grant /i);
 const original=await read('supabase/migrations/20261028000002_security_and_rpc.sql');
 const fn=original.slice(original.indexOf('create function public.submit_exercise('),original.indexOf('create function public.submit_written_response('));
 assert.equal(fn.split(broken).length,2);
 assert.ok(fn.replace(broken,fixed).includes(fixed));
});
test('pending submission migration cannot reintroduce the text CASE',async()=>{
 const pending=await read('supabase/migrations/20261028000004_submission_and_moderation.sql');
 assert.ok(pending.includes(fixed)); assert.ok(!pending.includes(broken));
});
test('hotfix bundle records history atomically and accepts only the inspected original baseline',async()=>{
 const out=await mkdtemp(path.join(os.tmpdir(),'fluentpath-hotfix-test-'));
 try{const sql=await prepareHotfix(out);
 assert.match(sql,/count\(\*\) from supabase_migrations.schema_migrations\)<>3/);
 assert.match(sql,/values\('20261028115000','progress_status_enum_hotfix'/);
 assert.match(sql,/commit;\s*$/);
 }finally{await rm(out,{recursive:true,force:true});}
});
