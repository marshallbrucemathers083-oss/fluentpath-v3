# Pre-deployment security and database audit

Assessment: **NO-GO for production application/deployment** until isolated PostgreSQL migration execution, regression testing, and role/concurrency verification succeed. Confirmed local defects below are fixed in the pending files. SQL/PLpgSQL syntax and behavior are reviewed statically, not certified by execution. Quiz marking investigation was deferred as requested; no marking investigation or production submission was performed.

## Evidence and scope

Read-only queries against project `grlwwmkjwhbxsnnfrovv` confirmed:

- Exactly the three original migrations are recorded, under versions `20261028113038`, `20261028113228`, and `20261028113820`. Their recorded names correspond to local migrations 1–3.
- Two profiles, both students; no existing admin. No identities or emails were needed for this audit.
- All 21 application tables have RLS enabled. The expected original policy names and option/exercise uniqueness constraints exist.
- No duplicate open report groups. `suspended_until` is absent, consistent with migration 4 remaining unapplied.
- Authenticated clients have SELECT only on profiles, reports, warnings, progress and XP. Signup's trusted trigger copies email/full name and does not accept a role from signup metadata.

Local environment: no PostgreSQL tools or installed embedded test engine; Docker socket access denied. No disposable database is available. **No pending migration, bootstrap, or database regression script was executed.** No remote writes, reset, push, or deployment occurred.

Validation: `npm test` passes six files. `node --test --test-isolation=none --test-reporter=spec` reports **27 passing tests**, including three added audit source-contract tests. Source-contract tests inspect safeguards; they are not proof of live RLS or SQL validity. Existing runtime frontend tests remain passing.

## Findings and documented local fixes

| ID | Severity | Finding and local fix |
|---|---|---|
| A1 | High / bootstrap blocker | Migration 4 required a non-null JWT actor for audit entries. Trusted owner-session role changes therefore failed. `moderation_history.actor_id` now permits null for system operations and records `actor_database_role DEFAULT session_user`. Ordinary RPC actions still record the actual user UUID. No client insert/update/delete grants or RLS write policies are provided for history; broad default table grants are explicitly revoked. |
| A2 | High / progress integrity | Migration 6 allowed changing an attempted lesson's exercise type/keys or appending exercises while retaining old progress and attempt IDs. It now rejects exercise edits/additions when that lesson has attempts or progress. Create a new lesson version instead. Existing notes and lesson metadata remain editable; history is not rewritten. |
| A3 | High / concurrency | Submission/start paths did not lock the parent lesson/set, allowing an admin edit to pass an attempt check while a learner was starting/submitting. Migration 4 now takes shared parent locks; admin content RPCs take exclusive parent locks and recheck draft state/attempts. Actual concurrent-session execution remains required. |
| A4 | High / restriction race | Some RPCs tested suspension before waiting for the profile lock, permitting a concurrent suspension to be missed. Relevant lesson, practice and community writes now take the profile lock before the effective restriction check, or recheck after acquiring it. |
| A5 | Medium / restore compatibility | The inherited `admin_set_user_ban(false)` cleared a ban but left temporary suspension active. Migration 7 now delegates this legacy API to the guarded, audited `restore` operation, clearing both restrictions. Existing frontend callers retain the same RPC signature. |
| A6 | Medium / idempotency | An existing report retry failed at the daily report limit even though it would not create a row. Migration 4 returns the existing open report before the rate check; profile locking, the partial unique index, and the new-report limit remain in place. |
| A7 | Medium / validation | A null moderation reason bypassed the length condition. The RPC now explicitly rejects null before any action. |
| A8 | Medium / migration staging | Direct authenticated exercise/key write grants remained available until migration 7. The revocation is now also in migration 6, where the validated content RPC is introduced. Complete the full sequence in a maintenance window before exposing the new admin application. |

Changes are confined to the four pending migrations, audit tests, and operator documentation/scripts. Original applied migrations remain unchanged. `supabase/admin-bootstrap.sql` and `supabase/predeployment-readonly.sql` are review templates, not migrations.

## Authorization and preservation review

- Public signup cannot select an admin role. Profile writes, XP, achievements, attempts and progress remain server-controlled. No client role-write policy or grant was introduced.
- New privileged public RPCs check `is_admin()` directly, or delegate to a checked operation. New functions revoke PUBLIC/anonymous execution and grant authenticated execution only. Existing `CREATE OR REPLACE` functions preserve their prior restricted ACLs. Definer functions pin an empty search path and qualify application relations.
- Content RLS permits administrator management; migration 7 removes moderator report/warning privileges and replaces moderation checks with administrator checks. Ordinary students can read their own reports and warnings, not other reporters' identities. Administrators can read reports and audit records; the context RPC excludes the reporter UUID. This is privacy from other members, not anonymity from authorized administrators.
- Exercise and exam keys remain restricted to admins through direct table RLS. Student delivery RPCs return sanitized option IDs/text. No answer keys were added to pre-submission payloads.
- Warnings do not restrict accounts. Reports do not warn or ban automatically. Content visibility and report disposition are independent administrative decisions. Suspensions expire by time comparison; restore clears both ban and suspension. Protected admin/self targets are rejected by the account moderation RPC.
- Audit history is append-only for application roles. Trusted database owners retain their inherent ability to modify data. A bootstrap/system entry has a null user actor plus the database login role, rather than a fabricated user identity.
- Migration 5 inserts new curriculum, sections, exercises/options, and a new practice set; it does not overwrite user-linked content or progress. Migrations 4/6 add nullable columns and new objects. None of the four files deletes users, progress, XP transactions or achievements, or retroactively recalculates awards. New configured lesson rewards affect future completion awards only; uniqueness prevents replay awards.
- Archived lessons cannot remain published after migration 7. Draft lessons must have notes and complete exercises before publishing, enforced by the existing trigger. New exam sets require complete objective questions. Attempted exam content is immutable through these RPCs. Direct admin lesson/section creation remains compatible with the current frontend; exercise/question writes must use the RPCs.

## Remaining risks and required release work

1. **Execute the full chain in an isolated PostgreSQL/Supabase test database.** Static inspection found no further confirmed syntax error; function compilation, triggers, RLS behavior, default privileges and lock ordering are unverified. Run `supabase/regression.sql` only there, then add independent-user report-privacy, expiry, forged-payload and concurrent-session cases.
2. **Migration history differs from local filename timestamps.** Pending filenames sort before the deployed recorded versions. Do not blindly run `supabase db push`, use `--include-all`, or mark/replay the original local files as new. An authorized operator must reconcile the original local-file/remote-history mapping and review the proposed plan, or execute only the four approved SQL bodies in order with an explicit migration-history recording plan. This audit changed no history.
3. **Non-idempotent migrations:** each file is transactional but the four-file batch is not atomic. Already committed files must not be rerun. Migration 5 has unique slugs and an exam set insertion that should run exactly once. Collision or duplicate-open-report errors roll back the current file; stop, inspect and prepare a reviewed remedy. Never delete reports/content to force a migration through.
4. Re-run `supabase/predeployment-readonly.sql` immediately before approval/application. Duplicate groups or curriculum slug/title collisions may appear after this audit. Compare per-account/progress/XP/achievement snapshots in a quiet window; aggregate row counts alone cannot prove row-level preservation.
5. Use a maintenance window: index creation and parent/profile locks can block traffic, and partial rollout can expose a mixed permission state. An older admin client that writes exercises/options directly will be denied after migration 6; deploy the matching RPC-based client only after the database changes pass verification.
6. Intentional workflow changes: moderators lose admin operations; used lessons require a new exercise version; attempted practice sets cannot be edited in place; archived lessons must be restored before publishing. Verify these errors are actionable for administrators. Learners retain own-record reads and profile maintenance; restrictions apply to learning submissions and community writes, not total Auth session revocation.
7. Roster pagination remains capped at 500 in the existing API; platform totals use a separate aggregate RPC. Authenticated responsive browser and end-to-end admin workflows remain unverified. No production readiness claim is made for them.

## Exact execution order after approval

The original three migrations are already applied and **must not be reapplied**.

1. `20261028000004_submission_and_moderation.sql`
2. `20261028000005_scenario_curriculum.sql`
3. `20261028000006_admin_content.sql`
4. `20261028000007_admin_workflows.sql`

Migration 4 depends on the original tables/types/helpers and adds suspension/audit state. Migration 5 needs the original publish trigger and content schema. Migration 6 adds archival metadata and the content RPC; migration 7 needs both migration 4's moderation state and migration 6's archive column. Complete the sequence before exposing new functionality. Do not execute the bootstrap before migration 4; use it only after the complete verified sequence.

## Safe first-admin bootstrap

Safe in design, pending database verification; **no account has been selected or promoted**.

1. The owner explicitly selects exactly one existing `auth.users.id`; independently verify the email/account belongs to the intended administrator and has a confirmed email and no active restrictions. Do not infer a target from signup metadata, display name, first registration or email domain.
2. Review `supabase/admin-bootstrap.sql`. Fill its two deliberately null constants with that approved UUID and verified email. Leave this operator-only SQL out of browser code, migrations and public RPCs.
3. After explicit approval, run the reviewed template using a trusted database-owner session without a user JWT. It locks profiles briefly, refuses if any admin already exists, verifies the UUID/email pair and email confirmation, updates exactly that account, and requires an audit entry. Any exception rolls back the transaction.
4. Read back the selected UUID's role, the total admin count (exactly one for this bootstrap), and the system audit entry. Sign in as that user and test authorized operations; independently sign in as a student and verify denial. Fresh navigation reloads the profile role; no custom client claim grants authority.
5. Never give a service-role secret to the browser or add role selection to registration. Subsequent privilege changes require an already-authorized admin or a separately reviewed owner operation. The current role RPC protects existing admins; emergency demotion is therefore a trusted-owner task and must preserve an audit entry and another recovery path.

## Post-migration verification checklist

- [ ] Confirm only the four approved new versions were recorded, with no original migration replay.
- [ ] Compare pre/post existing account IDs, roles (before bootstrap), XP totals and transaction rows, progress and achievement rows; verify no unexpected changes.
- [ ] Confirm new columns, audit table RLS, expected policies and execute/table grants. Anonymous/student/moderator calls to every admin RPC must fail. Direct student profile-role/XP/key/history writes must fail.
- [ ] Register with forged `role=admin` metadata; confirm student. Verify student lesson/practice delivery contains no key or explanation fields before submission.
- [ ] Exercise create/edit/unpublish/publish/archive/restore on a new test lesson. Reject incomplete choices, wrong-parent option IDs, malformed data, used-lesson edits and archived publication. Verify rollback leaves no partial exercises/options.
- [ ] Create and publish a complete draft practice set; reject incomplete sets and edits/additions to attempted sets. Verify ongoing attempts survive unpublishing and normal finish persistence.
- [ ] Report a post/reply twice; confirm same open report ID. At the limit, retry that report successfully and reject a genuinely new report. Verify reporter A cannot read reporter B's report.
- [ ] Warn, temporarily suspend, expire, ban and restore a test member. Verify database RPC denial while restricted and success after restoration, including the legacy restore endpoint. Test concurrent restriction/submission and content-edit/start calls.
- [ ] Dismiss/resolve reports and hide/remove/restore content; verify logs retain actor, target, before/after state and reason where supplied, while ordinary members cannot read/write history.
- [ ] Bootstrap only the approved account; verify trusted-system audit provenance, admin access, and unchanged privileges for every other account.
- [ ] Run isolated regression SQL and all Node tests; complete authenticated browser/mobile admin and student smoke tests before deployment approval.

## Failure and rollback

Take a restorable backup/snapshot before approved changes. Each failed SQL file rolls back its own transaction; earlier committed files remain. Keep the site in maintenance mode after any failure. Do not rerun committed files or the original migrations. For post-commit rollback, prepare an explicit compensating migration restoring prior RPCs/policies/grants and matching frontend behavior. Preserve audit/suspension state and retain new curriculum as unpublished rather than deleting user-linked rows. Reverting only the frontend can break admin writes after grant revocation; review both layers together. Test the restoration path in the isolated database before production approval.
