# Normal PostgreSQL RLS verification

## Current result

**NO-GO pending owner execution.** This Codex sandbox cannot create an IPv4 socket: a direct Python socket attempt returned `PermissionError: [Errno 1] Operation not permitted`. `psql` to the exact supplied target exited 2 before connection. The normal runner stopped at its first guard. No database fixture, migration or account was created from this sandbox, and no production connection was attempted.

| Scenario | Actual result here |
|---|---|
| Connect to disposable normal server | FAIL: sandbox socket restriction |
| RLS active for every protected public table | NOT RUN |
| Student progress/report/XP/achievement isolation | NOT RUN |
| Student admin RPC and self-promotion denial | NOT RUN |
| Administrator content and moderation workflows | NOT RUN |
| Restricted exercise/community writes | NOT RUN |
| Restore/unban and audit history | NOT RUN |
| Student answer-key privacy | NOT RUN |
| Migration preservation and exercise XP idempotency | NOT RUN |
| Existing regression and postflight in normal sessions | NOT RUN |

Python compilation and preparation-only generation succeed. Those are runner checks, not SQL/RLS passes. Existing single-user results do not change this table.

## Exact owner commands outside Codex

Use the existing Arch Linux terminal in the project directory:

```sh
cd /home/rezon/fluentpath-v3
psql -X -h 127.0.0.1 -p 55432 -U rezon -d fluentpath_rls_test \
  -c 'select current_database(),current_user,inet_server_addr(),inet_server_port();'
python3 scripts/test-rls-normal.py
```

If local authentication requires a password, use the local test server's protected `.pgpass` configuration; do not paste credentials into source files or terminal transcripts. The runner disables interactive password prompts and uses only the exact local host/port/database/user above. It strips other PG connection environment overrides. No Supabase tools, remote URLs, dependency installs, browser, or production credentials are used.

The runner creates a private `/tmp/fluentpath-normal-rls-*` directory containing each SQL stage, its actual `psql` output, and `results.json`. A successful invocation exits 0. Any setup failure stops immediately; independent scenario failures are recorded as FAIL and produce a final nonzero exit. Send back the final summary/results and failed-stage diagnostics, excluding credentials.

For review without connecting or changing any database:

```sh
python3 scripts/test-rls-normal.py --prepare-only
```

## Scope and safety guards

- The target must be `127.0.0.1:55432/fluentpath_rls_test`, owner `rezon`. Setup refuses existing public/Auth/history tables or views. It never resets a database or deletes existing tables/data. If this dedicated database is already populated, stop and inspect it; do not bypass the guard or point at another database.
- Setup requires the local owner to be a superuser only to create the synthetic Auth fixture/roles and switch session authorization. The `anon`/`authenticated` roles are created only if missing. Existing privileged or inherited roles cause refusal rather than alteration; PostgreSQL roles are cluster-wide, so use an isolated test cluster.
- Only synthetic `.invalid` identities are inserted. Originals 1–3 and the enum hotfix are applied to this empty disposable database, followed by 00004–00007 in order. These are test setup operations, never production replay. Test history records reflect the SQL actually executed.
- Student B earns real exercise progress/XP before the four migrations. Before/after normalized fingerprints must match. The guarded admin bootstrap promotes only synthetic admin UUID `00000000-0000-4000-8000-000000000203` in the disposable database. No production account is selected.
- Each scenario starts a fresh normal `psql` connection. It uses `SET SESSION AUTHORIZATION authenticated`, verifies both `current_user` and `session_user`, rejects superuser/BYPASSRLS roles, and asserts `row_security_active()` for every public application table before any scenario query. This deliberately fails in single-user mode.
- Synthetic student/admin identities use the same effective `authenticated` role plus an Auth UID setting, matching Supabase's role/verified-JWT model. The trusted harness sets that UID; it does not test the real Auth server's JWT validation or treat arbitrary raw SQL clients as a safe JWT gateway.
- The original full regression script runs including its final RLS assertions, without removing/rewriting production migration SQL. Postflight and the enum regression also run. No production migration file is modified to force a pass.
- Tests cover progress/report/XP/achievement isolation, sanitized delivery payloads, direct key-table denial, eleven admin RPC denials, direct role/XP write denial, publishing/edit/archive, practice creation, report context/dismissal/removal/restoration, warning/suspend/ban/unban, restricted writes, audit events, existing progress and replay-safe XP.

## Remediation rules

- Connection failure: run outside the Codex sandbox, check the local server's listening address, `pg_hba.conf`, local credentials and the exact database name. Do not substitute production.
- Empty-database guard: the runner has not authorized erasing the current contents. Review existing state before arranging a fresh dedicated database; never reset another local database.
- Privileged application role or inactive RLS: use a clean isolated cluster with non-superuser/NOBYPASSRLS application roles. Do not weaken the assertions or claim success under the owner.
- Migration/SQL failure: retain the exact failing SQL and log. Do not change production migrations merely to make tests green; distinguish a fixture defect from an application defect and review any proposed fix separately.
- Isolation/privilege/privacy failure: **NO-GO**. Preserve the effective role, UID, failed assertion and relevant policy/grant output; repair the proven authorization defect before release.
- XP/progress mismatch or duplicate award: **NO-GO**. Compare the logged fingerprints and reward transaction sources; do not delete progress or suppress the assertion.
- The runner leaves successful setup/test records intact for investigation. It refuses a blind whole-suite rerun against that now-populated database. If a scenario fails, inspect its saved SQL/log and the committed test state before deciding whether to run that scenario alone or prepare a new explicitly disposable database.

## Minimum remaining owner actions

1. Execute the normal runner outside Codex and return `results.json` plus any failure log.
2. If all SQL/RLS scenarios pass, complete authenticated browser smoke tests and review any concurrency requirements separately. This runner uses independent sessions sequentially; it is not a concurrent race test or full Supabase Auth/PostgREST integration test.
3. Only then approve the separate main-project admin migration/bootstrap plan. This test command performs no production release action.
