# Final admin release verification

## Recommendation

**NO-GO for an unconditional production release** until ordinary multi-session RLS/privacy and authenticated browser smoke checks pass. The SQL application/compilation blocker is now cleared in a disposable local PostgreSQL 18.6 database. The prepared sequence is compatible with the live enum hotfix. No main-project writes, promotions, pushes or deployments were performed.

## Confirmed live state

Read-only verification of `grlwwmkjwhbxsnnfrovv` found exactly:

| Version | Name |
|---|---|
| `20261028113038` | `20261028000001_schema` |
| `20261028113228` | `20261028000002_security_and_rpc` |
| `20261028113820` | `20261028000003_seed_curriculum` |
| `20261028115000` | `progress_status_enum_hotfix` |

The live `submit_exercise(uuid,uuid)` contains both explicit progress-status casts. Pending source migration 00004 also retains those casts. Do not replay any of these four applied migrations.

At inspection: two student accounts, no admins, 165 total XP, one progress row, two awarded achievements and six XP transactions. These are observations, not fixed preflight expectations: re-snapshot in a quiet window immediately before application. No duplicate open report groups, scenario slug collisions or new practice-title collisions were found; the pending suspension column is still absent. Existing application tables have RLS, profile UPDATE is not granted to students, and the signup trigger does not accept an admin role from metadata. Expected policy names for replacement are present.

## Validation performed

- `npm test`: eight files pass; explicit Node reporter: **32 tests pass**.
- `npm run build` and `npm run release:prepare`: pass; four guarded bundles regenerated under `/tmp/fluentpath-release`, with source hashes in the manifest.
- `python3 scripts/test-sql-single.py`: creates a fresh, disposable UTF-8 PostgreSQL 18.6 cluster under `/tmp`, a minimal Supabase-compatible Auth/role fixture, applies originals and hotfix only to that disposable cluster, then executes all four guarded bundles and postflight. All compile/apply successfully. It exercises enum submission, correct/incorrect options, XP replay prevention, written practice, exam scoring, signup-role rejection, moderation restrictions, duplicate reports, audit events, legacy restore, and the guarded bootstrap using rollback-only fixture accounts. Those core RPC and bootstrap checks pass.
- First SQL execution exposed a variable/alias collision in the regression script's exercise loop. The test alias is fixed. No migration/app feature changed in this pass.
- **RLS execution is not verified by that runner.** Socket creation is denied, so the runner uses PostgreSQL single-user mode. This bypasses RLS even after `SET ROLE`; the final row-isolation assertions are explicitly excluded and reported as unverified. Static policy/grant inspection and SQL postflight pass, but are not a substitute for ordinary-role sessions. Multi-session locking/deadlock behavior and authenticated browser checks remain unverified. The fixture is not a full Supabase Auth/PostgREST environment.

## Safety and compatibility

The four pending migrations perform no destructive user/progress/XP/achievement data migration. Migration 5 adds new content with new IDs. Migration 4 replaces functions but does not call submission/reward RPCs during application; historical awards remain untouched. Used lesson/exam content cannot be rekeyed through the new editing RPCs. The enum fix survives function replacement.

Authorization remains in guarded definer RPCs and RLS; PUBLIC/anonymous execute access is revoked on new admin APIs. Moderation requires an unrestricted admin; reports never automatically ban. Own-report and own-warning reads do not expose other reporters to students. History is read-only for application roles and records trusted bootstrap provenance. Complete-content checks gate publishing, and archived lessons cannot remain published. These properties pass source/catalog checks; report privacy still requires the ordinary-role execution check noted above.

Preservation must be verified after migration: `supabase/release-preservation.sql` produces normalized row fingerprints for accounts, attempts, progress, XP transactions and achievements. Compare before bootstrap or smoke mutations, with users paused. Equal digests/counts demonstrate those rows did not change; a mismatch means stop and investigate. Do not infer preservation only from aggregate XP.

## Exact owner commands after explicit approval

Use a verified owner connection supplied securely as `FLUENTPATH_DB_URL`. Do not paste a database password into the repository or browser. Take a restorable backup, enter a quiet/maintenance window, review the generated SQL and source manifest, and test normal-role RLS in a disposable server first. The generated bundles expect exactly the four history records above and add their own history record atomically. Do not combine them with an auto-recording migration tool or run `supabase db push` against the mismatched original filename history.

Run in a shell that stops on failure:

```sh
set -eu
cd /home/rezon/fluentpath-v3
npm test
npm run build
npm run release:prepare -- /tmp/fluentpath-release
: "${FLUENTPATH_DB_URL:?Supply the independently verified owner connection securely}"
umask 077
psql -X --dbname "$FLUENTPATH_DB_URL" -v ON_ERROR_STOP=1 -f supabase/predeployment-readonly.sql
psql -X --dbname "$FLUENTPATH_DB_URL" -v ON_ERROR_STOP=1 -At -f supabase/release-preservation.sql > /tmp/fluentpath-preservation-before.txt
# Only after review/approval, in precisely this order:
psql -X --dbname "$FLUENTPATH_DB_URL" -v ON_ERROR_STOP=1 -f /tmp/fluentpath-release/20261028120004_submission_and_moderation.sql
psql -X --dbname "$FLUENTPATH_DB_URL" -v ON_ERROR_STOP=1 -f /tmp/fluentpath-release/20261028120005_scenario_curriculum.sql
psql -X --dbname "$FLUENTPATH_DB_URL" -v ON_ERROR_STOP=1 -f /tmp/fluentpath-release/20261028120006_admin_content.sql
psql -X --dbname "$FLUENTPATH_DB_URL" -v ON_ERROR_STOP=1 -f /tmp/fluentpath-release/20261028120007_admin_workflows.sql
psql -X --dbname "$FLUENTPATH_DB_URL" -v ON_ERROR_STOP=1 -f supabase/release-postflight.sql
psql -X --dbname "$FLUENTPATH_DB_URL" -v ON_ERROR_STOP=1 -At -f supabase/release-preservation.sql > /tmp/fluentpath-preservation-after.txt
diff -u /tmp/fluentpath-preservation-before.txt /tmp/fluentpath-preservation-after.txt
```

These generated versions correspond one-to-one to source files `20261028000004_submission_and_moderation.sql` through `20261028000007_admin_workflows.sql`. Do not run the source files separately as well. No hotfix execution command belongs in this release. On any error stop: the current file rolls back but earlier committed files remain. Do not rerun committed bundles or reset data. A separately approved full-release containment script is `supabase/release-containment.sql`; it unpublishes new content/disables editing without deleting user data. Partial releases need a state-specific remedy.

## Promote one approved existing account

After postflight and preservation comparison, obtain explicit approval for **one exact existing UUID and independently verified email**. No target is assumed by this report. Make a private review copy:

```sh
install -m 600 supabase/admin-bootstrap.sql /tmp/fluentpath-approved-admin.sql
```

Edit only `selected_account uuid := null` and `expected_email text := null` in the private copy to the approved UUID and exact email. Review the resulting SQL. Using the trusted owner connection with no user JWT, after separate promotion approval:

```sh
psql -X --dbname "$FLUENTPATH_DB_URL" -v ON_ERROR_STOP=1 -f /tmp/fluentpath-approved-admin.sql
psql -X --dbname "$FLUENTPATH_DB_URL" -v ON_ERROR_STOP=1 -c "select role,count(*) from public.profiles group by role; select actor_id,actor_database_role,target_id,action,created_at from public.moderation_history where action='profiles:UPDATE' order by created_at desc limit 5;"
```

The template verifies UUID/email, confirmed email, no active restriction, no existing admin and an audit record; failure rolls back. Verify exactly one administrator and the approved target UUID in its audit row. Sign out/in and open `/app.html#/admin`. Confirm a separate student account is denied direct admin RPCs. Never use an email-only UPDATE, registration metadata, or frontend service-role key.

## Post-migration checklist and minimum owner actions

- [ ] Complete ordinary-role report/key/history privacy and concurrent-session checks in an accessible disposable server; complete student/admin browser smoke tests.
- [ ] Approve the four regenerated bundles, verify target/backup, execute in order, and confirm eight total history records with no baseline/hotfix replay.
- [ ] Run postflight and compare preservation fingerprints before any bootstrap/user activity.
- [ ] Separately approve one account and execute the guarded bootstrap; verify one admin and its audit row.
- [ ] Test lesson creation/edit/publish/unpublish/archive, practice management, report/dismiss/resolve, warn/suspend/ban/restore, content removal/restoration and audit visibility. Student B must not read student A's reports; students must not read answer keys or execute admin RPCs. Confirm Check Answer and XP persistence still work.
- [ ] Deploy the already prepared `dist/` only if separately approved; no UI redesign or new feature is needed for this release.
