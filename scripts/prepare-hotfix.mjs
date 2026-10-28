import { readFile,mkdir,writeFile } from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { baseline } from './prepare-release.mjs';
export async function prepareHotfix(out='/tmp/fluentpath-hotfix') {
 const file='20261028115000_progress_status_enum_hotfix.sql';
 const source=await readFile(new URL('../supabase/migrations/'+file,import.meta.url),'utf8');
 if(!/^--[^\n]*\nbegin;\s/i.test(source)||!/commit;\s*$/i.test(source)) throw new Error('Unexpected transaction boundaries');
 const body=source.replace(/^--[^\n]*\nbegin;\s*/i,'').replace(/commit;\s*$/i,'');
 const quote=s=>"'"+s.replaceAll("'","''")+"'";
 const expected=baseline.slice(0,3).map(([v,n])=>`(${quote(v)},${quote(n)})`).join(',');
 const bundle=`-- Owner-reviewed standalone hotfix plus atomic history recording.\nbegin;\nset local lock_timeout='10s';\nset local statement_timeout='30s';\nselect pg_advisory_xact_lock(7271143001);\ndo $history$ begin\n if (select count(*) from supabase_migrations.schema_migrations)<>3 or exists(select 1 from (values ${expected}) e(version,name) where not exists(select 1 from supabase_migrations.schema_migrations m where m.version=e.version and m.name=e.name)) then raise exception 'History differs from the inspected three-migration baseline; stop'; end if;\nend $history$;\n${body}\ninsert into supabase_migrations.schema_migrations(version,name,statements) values('20261028115000','progress_status_enum_hotfix',array[${quote(source)}]::text[]);\ncommit;\n`;
 await mkdir(out,{recursive:true}); await writeFile(path.join(out,file),bundle);
 await writeFile(path.join(out,'manifest.json'),JSON.stringify({file,sha256:createHash('sha256').update(source).digest('hex'),requires:baseline.slice(0,3)},null,2)+'\n');
 return bundle;
}
if(process.argv[1]===new URL(import.meta.url).pathname){const out=process.argv[2]||'/tmp/fluentpath-hotfix'; await prepareHotfix(out); console.log(`Prepared standalone hotfix in ${out}; no database connection made.`);}
