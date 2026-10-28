import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp,readFile,readdir,rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { buildSite } from '../scripts/build-site.mjs';
import { prepareRelease,pending } from '../scripts/prepare-release.mjs';
test('public build excludes SQL answer keys and operator files and contains only deployable assets', async()=>{
 const files=await buildSite();
 for(const blocked of ['supabase','docs','tests','scripts','.env','package.json']) assert.ok(!files.includes(blocked));
 assert.ok(files.includes('404.html')); assert.ok(files.includes('app.html'));
 for(const file of files.filter(f=>f.endsWith('.js'))){
  const text=await readFile(path.join('dist',file),'utf8');
  for(const match of text.matchAll(/from ['"](\.[^'"]+)['"]/g)) assert.ok(files.includes(path.normalize(path.join(path.dirname(file),match[1]))),`${file}: missing ${match[1]}`);
 }
});
test('release bundles preserve reviewed SQL and reconcile history without replaying baseline',async()=>{
 const out=await mkdtemp(path.join(os.tmpdir(),'fluentpath-release-test-'));
 try{
  await prepareRelease(out);
  const files=await readdir(out); assert.equal(files.filter(f=>f.endsWith('.sql')).length,4);
  for(const item of pending){
   const sql=await readFile(path.join(out,`${item.version}_${item.name}.sql`),'utf8');
   const source=await readFile(path.join('supabase/migrations',item.source),'utf8');
   assert.ok(sql.includes(source.replace(/^--[^\n]*\nbegin;\s*/i,'').replace(/commit;\s*$/i,'')));
   assert.match(sql,/Migration history differs from reviewed release plan/);
   assert.match(sql,/insert into supabase_migrations.schema_migrations/);
   assert.ok(item.version>'20261028113820');
   assert.match(sql,/commit;\s*$/);
  }
 }finally{await rm(out,{recursive:true,force:true});}
});
