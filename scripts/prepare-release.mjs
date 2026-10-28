import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';
export const baseline = [
 ['20261028113038','20261028000001_schema'],
 ['20261028113228','20261028000002_security_and_rpc'],
 ['20261028113820','20261028000003_seed_curriculum'],
 ['20261028115000','progress_status_enum_hotfix']
];
export const pending = ['submission_and_moderation','scenario_curriculum','admin_content','admin_workflows'].map((name,i)=>({ source:`2026102800000${i+4}_${name}.sql`, version:`2026102812000${i+4}`, name }));
const literal = value => "'"+value.replaceAll("'","''")+"'";
export async function prepareRelease(out) {
 await mkdir(out,{recursive:true}); const manifest=[];
 for (const [index,item] of pending.entries()) {
  const source=await readFile(new URL('../supabase/migrations/'+item.source,import.meta.url),'utf8');
  if (!/^--[^\n]*\nbegin;\s/i.test(source) || !/commit;\s*$/i.test(source)) throw new Error('Unexpected transaction boundary: '+item.source);
  const body=source.replace(/^--[^\n]*\nbegin;\s*/i,'').replace(/commit;\s*$/i,'');
  const expected=[...baseline,...pending.slice(0,index).map(p=>[p.version,p.name])];
  const rows=expected.map(([v,n])=>`(${literal(v)},${literal(n)})`).join(',');
  const bundle=`-- Generated from ${item.source}; review before approved owner execution.\nbegin;\nset local lock_timeout='10s';\nset local statement_timeout='120s';\nselect pg_advisory_xact_lock(7271143001);\ndo $release$ begin\n if exists(select 1 from (values ${rows}) e(version,name) where not exists(select 1 from supabase_migrations.schema_migrations m where m.version=e.version and m.name=e.name)) or (select count(*) from supabase_migrations.schema_migrations)<>${expected.length} then raise exception 'Migration history differs from reviewed release plan; stop without replaying migrations'; end if;\nend $release$;\n${body}\ninsert into supabase_migrations.schema_migrations(version,name,statements) values(${literal(item.version)},${literal(item.name)},array[${literal(source)}]::text[]);\ncommit;\n`;
  const file=`${item.version}_${item.name}.sql`;
  await writeFile(path.join(out,file),bundle);
  manifest.push({...item,file,sha256:createHash('sha256').update(source).digest('hex')});
 }
 await writeFile(path.join(out,'manifest.json'),JSON.stringify({baseline,migrations:manifest},null,2)+'\n');
 return manifest;
}
if(process.argv[1]===new URL(import.meta.url).pathname){const out=process.argv[2]||'/tmp/fluentpath-release'; await prepareRelease(out); console.log(`Prepared four review-only bundles in ${out}; no database connection made.`);}
