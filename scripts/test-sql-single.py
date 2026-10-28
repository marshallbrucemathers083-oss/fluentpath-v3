"""Disposable PostgreSQL checks without sockets. No network or remote connections."""
from pathlib import Path
import subprocess, tempfile, re, sys
root = Path(__file__).resolve().parent.parent
cluster = Path(tempfile.mkdtemp(prefix='fluentpath-sql-check-')) / 'data'
subprocess.run(['initdb','-D',str(cluster),'-A','trust','--no-locale','-E','UTF8'],check=True,stdout=subprocess.DEVNULL)
def execute(label, sql):
    # Single-user -j ends a command at a blank line; keep the whole script together.
    command = '\n'.join(line for line in sql.splitlines() if line.strip()) + '\n\n'
    result = subprocess.run(['postgres','--single','-j','-D',str(cluster),'postgres'],input=command,text=True,capture_output=True)
    (cluster.parent / (re.sub(r'[^a-zA-Z0-9_-]','_',label)+'.log')).write_text(result.stdout+result.stderr)
    if result.returncode or re.search(r'\b(ERROR|FATAL|PANIC):',result.stderr):
        print('FAIL:',label);print(result.stderr);sys.exit(1)
    print('PASS:',label)
execute('Supabase-compatible minimal fixture', '''
create role anon nologin;
create role authenticated nologin;
create schema extensions;
create schema auth;
create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}',email_confirmed_at timestamptz);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
grant usage on schema auth to anon,authenticated;
create schema supabase_migrations;
create table supabase_migrations.schema_migrations(version text primary key,name text,statements text[]);
''')
for file in sorted((root/'supabase/migrations').glob('2026102800000[123]_*.sql')):
    execute(file.name,file.read_text())
execute('Record executed local baseline', "insert into supabase_migrations.schema_migrations(version,name) values ('20261028113038','20261028000001_schema'),('20261028113228','20261028000002_security_and_rpc'),('20261028113820','20261028000003_seed_curriculum');")
subprocess.run(['node','scripts/prepare-hotfix.mjs',str(cluster.parent/'hotfix')],cwd=root,check=True)
execute('standalone hotfix bundle',(cluster.parent/'hotfix/20261028115000_progress_status_enum_hotfix.sql').read_text())
execute('authenticated enum regression',(root/'supabase/enum-hotfix-regression.sql').read_text())
subprocess.run(['node','scripts/prepare-release.mjs',str(cluster.parent/'release')],cwd=root,check=True)
for file in sorted((cluster.parent/'release').glob('*.sql')):execute(file.name,file.read_text())
execute('release postflight',(root/'supabase/release-postflight.sql').read_text())
regression=(root/'supabase/regression.sql').read_text()
# PostgreSQL single-user mode bypasses RLS even after SET ROLE. Do not claim RLS coverage.
execute('core RPC regression - RLS assertions excluded',regression.split('set local role authenticated;')[0]+'\nrollback;')
bootstrap=(root/'supabase/admin-bootstrap.sql').read_text().replace('selected_account uuid := null',"selected_account uuid := '00000000-0000-4000-8000-000000000111'").replace('expected_email text := null',"expected_email text := 'bootstrap-fixture@fluentpath.invalid'")
bootstrap=bootstrap.replace('begin;','',1).rsplit('commit;',1)[0]
execute('guarded bootstrap fixture rollback',"begin; insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values('00000000-0000-4000-8000-000000000111','bootstrap-fixture@fluentpath.invalid',now(),'{}');\n"+bootstrap+'\nrollback;')
print('RLS isolation and multi-session concurrency remain UNVERIFIED: single-user backend bypasses RLS.')
print('Disposable cluster and logs retained at',cluster.parent)
