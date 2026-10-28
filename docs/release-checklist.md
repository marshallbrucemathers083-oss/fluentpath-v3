# Final stabilization release plan

Latest verified admin-release state, local PostgreSQL results, and exact owner commands: `docs/admin-release.md`. Its confirmed live hotfix history supersedes the historical pre-hotfix status below.

**Urgent update:** apply the independently approved `20261028115000_progress_status_enum_hotfix.sql` first using `docs/enum-hotfix.md`. The exact submission failure is now confirmed. Regenerated admin bundles require that hotfix history record; old bundles/manifests are stale. No main-project write has occurred. References below to a three-record preflight describe the pre-hotfix state; the later admin-bundle preflight now requires four records including the hotfix.

**Status: NO-GO pending isolated SQL execution and authenticated browser verification.** No remote write, account promotion, deployment, reset or push was performed. The deferred marking complaint was not investigated.

## Completed locally

- Reviewed the seven migration files and the security audit. Existing authorization, restriction checks, immutable attempted content and audit safeguards remain in place.
- Read-only main-project check confirmed the same three applied migrations, no pending suspension column, zero existing scenario slugs, zero duplicate open-report groups, and no admin account.
- Reconciled the migration-history mapping **in a generated owner execution plan**, without modifying remote history or replaying schema/seed SQL. The bundle validates the entire expected history before each file, runs the reviewed body once, and records its new version in that same transaction. A history mismatch, repeat execution or SQL failure stops the file.
- Fixed the release artifact: publishing repository root would expose seed answer keys. `npm run build` now emits only public HTML/CSS/JS and Pages headers/routes into `dist/`. Added a real generated 404 page and removed the obsolete 404 rewrite. Do not deploy the repository root or make its answer-key SQL public in a repository.
- Removed the student error-screen link to operator-only setup documentation, which is excluded from the artifact. Updated stale deployment/bootstrap instructions.
- Added public-artifact and migration-bundle tests. **29 Node tests pass** across seven test files; `npm run build` and `npm run release:prepare` succeed. Local asset targets and relative JS imports are checked. No secret key/private key was found in the emitted public artifact. This workspace has no Git metadata, so Git history/staged-secret review cannot be certified.

## Exact history mapping

The first three remote records are retained unchanged:

| Local original | Already-applied remote version | Recorded name |
|---|---|---|
| `20261028000001_schema.sql` | `20261028113038` | `20261028000001_schema` |
| `20261028000002_security_and_rpc.sql` | `20261028113228` | `20261028000002_security_and_rpc` |
| `20261028000003_seed_curriculum.sql` | `20261028113820` | `20261028000003_seed_curriculum` |

Pending reviewed source files map to later release records:

| Pending source | Generated bundle / release version |
|---|---|
| `20261028000004_submission_and_moderation.sql` | `20261028120004_submission_and_moderation.sql` |
| `20261028000005_scenario_curriculum.sql` | `20261028120005_scenario_curriculum.sql` |
| `20261028000006_admin_content.sql` | `20261028120006_admin_content.sql` |
| `20261028000007_admin_workflows.sql` | `20261028120007_admin_workflows.sql` |

This is an explicit owner-run SQL release path, not permission to run `supabase db push` on the original migration directory. That directory's timestamps differ from live history. Do not run history repair, `--include-all`, or the original three files on production. Future CLI adoption must use a separately reviewed filename/history alignment. The manifest includes the source SHA-256 values; regenerate and re-review if a source changes.

## Database execution limitation

No `psql`, `postgres`, `initdb`, or Supabase CLI is available here. Docker is installed but its socket denies access. No installed embedded PostgreSQL is available. No isolated database was run, and production was not used as a substitute. Therefore SQL syntax/function compilation, grants, RLS behavior, trigger execution, migration history insertion, concurrency and regression SQL remain **unverified by execution**.

The smallest viable test environment is a fresh local Supabase database with its Auth schema, standard roles and `auth.uid()` helper. An empty generic PostgreSQL database alone does not supply those dependencies. In that disposable environment only, execute original migrations 1–3 once, record their three baseline version/name pairs as above in its local `supabase_migrations.schema_migrations`, then run the four bundles and `supabase/regression.sql`. Do not stamp a baseline that was not actually executed. Never execute that fixture setup or regression script on the main project. If a cloned baseline test environment is used instead, do not replay originals there either.

## Owner execution commands after testing and explicit approval

Run from the project root using `psql` and an owner connection supplied outside the repository. Keep credentials out of shell history, logs and frontend code. `FLUENTPATH_DB_URL` must identify the reviewed target; verify the host/project independently before setting it. Prefer an existing protected PostgreSQL password/service configuration. The following commands are **prepared, not executed**:

```sh
set -eu
npm test
npm run build
npm run release:prepare -- /tmp/fluentpath-release
# Review manifest.json and all four generated SQL files before authorizing execution.
# Supply FLUENTPATH_DB_URL securely; do not paste its value into this document.
: "${FLUENTPATH_DB_URL:?Set the verified owner connection outside the repository}"
psql -X --dbname "$FLUENTPATH_DB_URL" -v ON_ERROR_STOP=1 -f supabase/predeployment-readonly.sql
```

Before proceeding: take a restorable backup, put the application in a maintenance window, retain private per-row snapshots of accounts/progress/XP/achievements, confirm zero report duplicates and seed collisions, and verify the exact three-record baseline. Preflight results contain user IDs and should be stored privately. If a check differs from this plan, stop. The bundles also fail closed on changed migration history.

After explicit approval, execute these four commands in this exact order, stopping on the first error:

```sh
psql -X --dbname "$FLUENTPATH_DB_URL" -v ON_ERROR_STOP=1 -f /tmp/fluentpath-release/20261028120004_submission_and_moderation.sql
psql -X --dbname "$FLUENTPATH_DB_URL" -v ON_ERROR_STOP=1 -f /tmp/fluentpath-release/20261028120005_scenario_curriculum.sql
psql -X --dbname "$FLUENTPATH_DB_URL" -v ON_ERROR_STOP=1 -f /tmp/fluentpath-release/20261028120006_admin_content.sql
psql -X --dbname "$FLUENTPATH_DB_URL" -v ON_ERROR_STOP=1 -f /tmp/fluentpath-release/20261028120007_admin_workflows.sql
psql -X --dbname "$FLUENTPATH_DB_URL" -v ON_ERROR_STOP=1 -f supabase/release-postflight.sql
psql -X --dbname "$FLUENTPATH_DB_URL" -v ON_ERROR_STOP=1 -f supabase/predeployment-readonly.sql
```

The bundles set 10-second lock and 120-second statement timeouts. On timeout, stop and inspect; do not weaken safeguards to rush through. Each file and its history record commit together. Earlier successful files remain committed if a later one fails. Compare existing rows, IDs and awards with the snapshots; baseline student roles and all progress/XP/achievement rows must be unchanged by migration execution.

## Bootstrap exactly one approved administrator

After all four bundles and postflight pass, independently select one existing verified account by UUID and confirmed email. Fill only the two null constants in a privately reviewed copy of `supabase/admin-bootstrap.sql`. Obtain explicit approval for that exact identity, then run the copy with the trusted owner connection and no user JWT. It refuses an existing admin, mismatched identity, unconfirmed email or restricted account; exactly one role change and its system audit record must be observed. No signup role selector or browser secret is required. **No account has been selected/promoted.**

## Rollback / containment

Keep the site in maintenance mode after any failure. Do not rerun committed bundles or remove history entries to force replay. A failed file rolls back its schema/data/history changes; inspect which prior versions committed.

After a fully committed release, `supabase/release-containment.sql` is a separately approved targeted containment option: unpublish only the new scenario lessons/practice set and disable new content-writing RPC execution. It preserves all users, submissions, progress, XP, achievements, logs, restrictions and security policies. It is deliberately **not** a full schema reversal; content editing is unavailable until a reviewed repair restores its grants. For a partial release, prepare a state-specific remedy instead of executing containment blindly. Keep the matching new frontend for student compatibility, or keep maintenance mode; an older frontend that directly writes exercise keys will fail under the new grants. Restore a backup only under a separately reviewed data-recovery plan.

## Authenticated smoke tests still required

Use a dedicated student account and the explicitly approved admin account, not production mutations disguised as tests. Run SQL regression in the disposable database only. On the approved test deployment check:

- Registration, confirmation email callback, login/logout, password recovery and expired-link feedback.
- Student dashboard, lesson retrieval, objective/written submission, saved progress and XP after reload; existing workflows may be blocked until all pending migrations are applied.
- Community post/reply, report reason/detail, duplicate handling, own-report status and privacy from another student.
- Practice start/resume/save/finish and persisted history; writing/speaking remain ungraded practice.
- Admin navigation, lesson create/edit/publish/unpublish/archive, practice questions, report context, warning, suspension/expiry, ban/restore, content remove/restore and retained audit history.
- Direct unauthenticated/student/moderator admin calls are denied; no pre-submission keys leak. Existing attempted content cannot be rekeyed.
- Mobile menu, keyboard focus, readable narrow layout and reduced-motion behavior at 390px and desktop widths.

Code paths and static contracts were reviewed; none of these authenticated workflows is certified as browser-tested here. The sandbox denied opening an HTTP server socket; the prior Firefox attempt exited 139. Static layout source review is not mobile browser validation.

## Smallest owner action set

1. Run the prepared SQL bundles/regression in an accessible disposable Supabase database and complete the two-account browser smoke test there; retain results.
2. Review/approve the four source-to-release mappings and backup/maintenance plan; execute only the four bundles on the main project, then postflight and preservation checks.
3. Approve one exact verified account for the guarded bootstrap.
4. Set the final HTTPS Auth URLs and approve/upload **only `dist/`** to Cloudflare Pages, then confirm callback and authorization behavior before ending maintenance mode. See `docs/deploy.md`.
