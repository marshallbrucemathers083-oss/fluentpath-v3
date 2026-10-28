"""Normal PostgreSQL RLS suite. Fixed disposable target; never uses Supabase/network APIs."""
import argparse, json, os, subprocess, tempfile, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
A='00000000-0000-4000-8000-000000000201'
B='00000000-0000-4000-8000-000000000202'
ADMIN='00000000-0000-4000-8000-000000000203'
parser=argparse.ArgumentParser()
parser.add_argument('--prepare-only',action='store_true')
args=parser.parse_args()
out=Path(tempfile.mkdtemp(prefix='fluentpath-normal-rls-'))
env={k:v for k,v in os.environ.items() if not k.startswith('PG') or k in ('PGPASSWORD','PGPASSFILE')}
env['PGCONNECT_TIMEOUT']='4'
command=['psql','-X','--no-password','-h','127.0.0.1','-p','55432','-U','rezon','-d','fluentpath_rls_test','-v','ON_ERROR_STOP=1','-At']
results=[]
def run(label,sql,critical=True):
    file=out/(str(len(results)).zfill(2)+'-'+''.join(c if c.isalnum() else '-' for c in label)+'.sql')
    file.write_text(sql)
    if args.prepare_only:return ''
    proc=subprocess.run(command,input=sql,text=True,capture_output=True,env=env)
    (file.with_suffix('.log')).write_text(proc.stdout+proc.stderr)
    ok=proc.returncode==0
    results.append({'scenario':label,'status':'PASS' if ok else 'FAIL','log':str(file.with_suffix('.log'))})
    print(('PASS: ' if ok else 'FAIL: ')+label,flush=True)
    (out/'results.json').write_text(json.dumps(results,indent=2)+'\n')
    if not ok:
        print(proc.stderr or 'psql connection failed without a diagnostic; check sandbox/network/authentication.',flush=True)
        if critical: print('NO-GO. Stopped; no reset/cleanup is performed. Logs:',out);sys.exit(1)
    return proc.stdout.strip()
def source(name):return (ROOT/name).read_text()
def session(uid,sql):
    # Equivalent to the effective authenticated role + verified JWT set by PostgREST.
    # SESSION AUTHORIZATION removes superuser/session-owner identity for all test queries.
    return f"""set session authorization authenticated;
select set_config('request.jwt.claim.sub','{uid}',false);
do $$ declare t record; begin
 if current_user<>'authenticated' or session_user<>'authenticated' then raise exception 'Wrong effective session identity'; end if;
 if exists(select 1 from pg_roles where rolname=current_user and (rolsuper or rolbypassrls)) then raise exception 'Privileged role would invalidate RLS test'; end if;
 for t in select c.oid,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' loop
 if not row_security_active(t.oid) then raise exception 'RLS INACTIVE: %',t.relname; end if;
 end loop;
end $$;
"""+sql
run('target and empty-database safety guard',"""do $$ begin
 if current_database()<>'fluentpath_rls_test' or inet_server_addr()<>'127.0.0.1'::inet or inet_server_port()<>55432 then raise exception 'Wrong test target'; end if;
 if current_user<>'rezon' then raise exception 'Wrong setup owner'; end if;
 if exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','auth','supabase_migrations') and c.relkind in ('r','p','v','m','f')) then raise exception 'Database is not empty: inspect it; this runner never resets or overwrites existing databases'; end if;
 if not exists(select 1 from pg_roles where rolname=current_user and rolsuper) then raise exception 'Fixture setup needs local superuser for roles and SESSION AUTHORIZATION; do not grant this to application roles'; end if;
end $$;
""")
run('minimal Supabase fixture and nonprivileged roles',"""do $$ declare r text; begin
 foreach r in array array['anon','authenticated'] loop
 if not exists(select 1 from pg_roles where rolname=r) then execute format('create role %I nologin nosuperuser nobypassrls',r); end if;
 if exists(select 1 from pg_roles where rolname=r and (rolsuper or rolbypassrls)) or exists(select 1 from pg_auth_members m join pg_roles p on p.oid=m.member where p.rolname=r) then raise exception 'Existing role % is privileged or inherits other roles; refusing to alter cluster roles',r; end if;
 end loop;
end $$;
create schema auth;
create schema extensions;
create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}',email_confirmed_at timestamptz);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
grant usage on schema auth to authenticated,anon;
create schema supabase_migrations;
create table supabase_migrations.schema_migrations(version text primary key,name text,statements text[]);
""")
for file in sorted((ROOT/'supabase/migrations').glob('2026102800000[123]_*.sql')):run('baseline '+file.name,file.read_text())
run('record actually executed baseline',"insert into supabase_migrations.schema_migrations(version,name) values ('20261028113038','20261028000001_schema'),('20261028113228','20261028000002_security_and_rpc'),('20261028113820','20261028000003_seed_curriculum');")
run('enum hotfix',source('supabase/migrations/20261028115000_progress_status_enum_hotfix.sql'))
run('record actually executed hotfix',"insert into supabase_migrations.schema_migrations(version,name) values ('20261028115000','progress_status_enum_hotfix');")
run('pre-existing synthetic learning records',f"""insert into auth.users(id,email,raw_user_meta_data,email_confirmed_at) values
('{A}','student-a@fluentpath.invalid','{{"full_name":"Student A","role":"admin"}}',now()),
('{B}','student-b@fluentpath.invalid','{{"full_name":"Student B"}}',now()),
('{ADMIN}','admin-fixture@fluentpath.invalid','{{"full_name":"Admin fixture"}}',now());
select set_config('request.jwt.claim.sub','{B}',false);
select public.submit_exercise(e.id,o.id) from public.exercises e join public.lessons l on l.id=e.lesson_id join public.exercise_options o on o.exercise_id=e.id where l.slug='a1-verb-to-be' and o.is_correct;
do $$ declare t uuid; begin t:=public.create_forum_thread('Student B private report fixture','Synthetic content for isolation tests.'); perform public.report_forum_content('thread',t,'Spam or advertising: B fixture'); end $$;
""")
before=run('capture preserved records before release',source('supabase/release-preservation.sql'))
for number,name in [(4,'submission_and_moderation'),(5,'scenario_curriculum'),(6,'admin_content'),(7,'admin_workflows')]:
    run('pending migration '+str(number),source(f'supabase/migrations/2026102800000{number}_{name}.sql'))
    run('record pending migration '+str(number),f"insert into supabase_migrations.schema_migrations(version,name) values ('2026102812000{number}','{name}');")
after=run('compare preserved records after release',source('supabase/release-preservation.sql'))
if not args.prepare_only and before!=after:
    print('FAIL: migration preservation fingerprints differ; NO-GO. Logs:',out);sys.exit(1)
run('existing postflight',source('supabase/release-postflight.sql'))
run('existing enum regression normal session',source('supabase/enum-hotfix-regression.sql'))
run('existing full regression INCLUDING RLS assertions',source('supabase/regression.sql'))
bootstrap=source('supabase/admin-bootstrap.sql').replace('selected_account uuid := null',f"selected_account uuid := '{ADMIN}'").replace('expected_email text := null',"expected_email text := 'admin-fixture@fluentpath.invalid'")
run('guarded synthetic admin bootstrap',bootstrap)
# Each scenario starts a new PostgreSQL connection. SQL checks switch JWT identities
# only as the trusted test harness, modeling independently verified gateway users.
for name,file,uid in [
 ('student isolation and answer-key privacy','student.sql',A),
 ('administrator authorization and self-promotion denial','denials.sql',A),
 ('admin content and moderation workflows','admin.sql',ADMIN),
 ('suspended and banned write restrictions and restoration','restrictions.sql',ADMIN),
]:run(name,session(uid,source('tests/sql/'+file)),critical=False)
run('anonymous administrator denial',"""set session authorization anon;
do $$ begin
 if exists(select 1 from pg_roles where rolname=current_user and (rolsuper or rolbypassrls)) then raise exception 'Privileged anon role'; end if;
 begin perform public.admin_platform_stats(); raise exception 'Anonymous admin RPC succeeded'; exception when insufficient_privilege then null; end;
end $$;
""",critical=False)
if args.prepare_only:
    print('PREPARED ONLY; nothing executed. Generated SQL:',out)
else:
    failed=any(r['status']=='FAIL' for r in results)
    print(('NO-GO: failures require remediation.' if failed else 'PASS: normal-session SQL suite. Browser/Auth gateway/concurrency checks are separate.'),'Results:',out/'results.json')
    sys.exit(1 if failed else 0)
