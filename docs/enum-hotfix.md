# Urgent exercise submission enum hotfix

## Confirmed root cause

Read-only inspection of project `grlwwmkjwhbxsnnfrovv` confirms `public.progress_status` has exactly `not_started`, `in_progress`, and `completed`. The live function `public.submit_exercise(uuid,uuid)` contains:

```sql
on conflict(user_id,lesson_id) do update set status=
 case when public.lesson_progress.status='completed'
 then 'completed' else 'in_progress' end,
 updated_at=now();
```

PostgreSQL resolves a CASE whose result branches are untyped string literals to `text`. That result cannot be assigned implicitly to the enum status column. The remote read-only `pg_typeof` check returned `text` for the original CASE and `progress_status` for the fixed CASE. This is a server exception, not a wrong answer verdict. The failing RPC transaction rolls back its attempted writes.

There are no non-internal triggers on `lesson_progress`. The only live functions writing it are `submit_exercise` and `submit_written_response`. The latter uses direct enum-context literals for insert/completion and has no affected CASE expression. Other enum columns were checked: RPC parameters such as role/level are typed enums, JSON/text content fields in pending RPCs use explicit enum casts, and seed values use enum-target context or explicit casts. Forum/exam status columns are text, so their text CASE assignments are appropriate. No other matching enum CASE defect was found.

## Exact fix

```sql
status = case when public.lesson_progress.status='completed'
 then 'completed'::public.progress_status
 else 'in_progress'::public.progress_status end
```

New minimal migration: `supabase/migrations/20261028115000_progress_status_enum_hotfix.sql`.

It reads the deployed function definition and replaces only the exact broken CASE expression using `CREATE OR REPLACE` from `pg_get_functiondef`. It retains the rest of the function, signature, owner, definer authorization, pinned search path and execute privileges. It stops on an unexpected definition instead of overwriting it, and accepts an already-fixed matching expression. It does not update user rows, answer keys, options, XP, achievements or attempts, and does not add privileges or depend on suspension/admin objects.

The original applied migration 2 is left unchanged. Pending migration `20261028000004_submission_and_moderation.sql` repeated the defect and was **not applied**; it has now been corrected locally so it cannot undo the fix. The other pending migrations do not fix this bug. Main-project history still contains only the original three migrations; no remote changes were performed.

## Verification

- `npm test`: eight test files pass.
- `node --test --test-isolation=none --test-reporter=spec`: **32 tests pass**.
- `npm run build`: passes.
- Hotfix and later release bundle preparation: passes; no database connection made.
- Remote read-only type check: original CASE is text; fixed CASE is the enum, and both branches return valid values.
- `supabase/enum-hotfix-regression.sql`: prepared but **not executed**. Run only in a disposable Supabase-compatible database with originals 1–3 and this hotfix. It tests an actual authenticated `are` submission, persisted completion and XP, repeat submission without duplicate XP, and wrong/in-progress then correct retry. Its fixture writes roll back. Never run fixture regression on production.
- No local PostgreSQL executable is available; hotfix DDL execution and authenticated post-fix submission remain unverified. No browser test or production write was substituted.

## Independent deployment and exact approval steps

This hotfix can be deployed independently of pending migrations 00004–00007. It is versioned after the actual last recorded baseline version `20261028113820` and before planned admin release versions `20261028120004`–`20261028120007`.

1. Review the hotfix source and test evidence. If an isolated database is available, apply only the hotfix after originals 1–3 and run the rollback-only regression there. Take a restorable backup and retain the current function definition/ACL before a main-project change.
2. Explicitly approve **only** `20261028115000_progress_status_enum_hotfix.sql` on project `grlwwmkjwhbxsnnfrovv`. No pending admin migration, account promotion or frontend deployment is required or included.
3. Generate the guarded owner bundle:

```sh
node scripts/prepare-hotfix.mjs /tmp/fluentpath-hotfix
```

Review its SQL and manifest. The bundle requires exactly the inspected three migration-history records, sets short timeouts, and records version `20261028115000` / name `progress_status_enum_hotfix` in the same transaction as the fix. Do not separately run the raw source and bundle or record the same migration twice.

4. After explicit approval, using the securely supplied verified owner connection, run:

```sh
psql -X --dbname "$FLUENTPATH_DB_URL" -v ON_ERROR_STOP=1 \
  -f /tmp/fluentpath-hotfix/20261028115000_progress_status_enum_hotfix.sql
```

Alternatively an authorized owner can execute that **generated bundle** in the Supabase SQL editor. Do not use an auto-recording migration tool on the bundle, because it already records history. If target history has changed, stop and review; do not replay the baseline or force the guard to pass.

5. Read back `pg_get_functiondef('public.submit_exercise(uuid,uuid)'::regprocedure)` and the new history record. Compare ACL/definer/search-path metadata with the snapshot. Have the learner retry “My friends ___ ready for class” with `are`, then reload to confirm saved progress/XP. This approved user retry is a real user action, not the rollback fixture test. If it fails, retain the exact new error and stop further rollout.
6. Regenerate future admin release bundles with `npm run release:prepare`. They now require this hotfix record and include the corrected migration 00004. Discard previously generated admin bundles/manifests; they are stale. No CLI history repair or original migration replay is necessary for the owner-bundle path.

On SQL failure, the hotfix bundle rolls back both definition and history changes. Do not roll back a successfully applied cast by restoring the known-broken CASE. If postflight reveals an unrelated function drift, use the captured definition for a separately reviewed targeted repair that retains enum-safe assignment. No data deletion or reset is needed.
