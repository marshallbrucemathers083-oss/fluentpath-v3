# Database migrations

The SQL migrations are versioned and intended for review before application. Run one file at a time in filename order; each file has an explicit transaction boundary. Migration 1 defines the schema and enables RLS immediately, with no policies yet. Migration 2 installs signup handling, policies, answer-safe RPCs, XP and score enforcement, staff functions, and forum moderation. Migration 3 seeds the curriculum and TOEFL practice set.

Exact order:

1. `20261028000001_schema.sql`
2. `20261028000002_security_and_rpc.sql`
3. `20261028000003_seed_curriculum.sql`

These three migrations have already been applied to project `grlwwmkjwhbxsnnfrovv`. Do not reapply them there. For a different project, inspect its migration history and current objects, then get explicit approval before remote changes. On failure, stop and fix the error before retrying that migration.

After successful application, the six read-only checks in `verify.sql` passed. The connected Supabase migration history records all three migration names.

The migration files remain the source artifacts for audit and future setup on a separate project.

Pending local changes, not applied remotely:

4. `20261028000004_submission_and_moderation.sql`
5. `20261028000005_scenario_curriculum.sql`
6. `20261028000006_admin_content.sql`
7. `20261028000007_admin_workflows.sql`

Review changes, risks, isolated verification, and rollback planning in `docs/v3-review.md`. New admin workflows require all pending migrations in order. `regression.sql` is a rollback-only test for an isolated test database, not production. Do not apply pending migrations to the connected project without explicit approval.
