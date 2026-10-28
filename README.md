# FluentPath V3

A vanilla HTML, CSS, and JavaScript English-learning platform. It uses Supabase Auth and PostgreSQL, with Cloudflare Pages as the static hosting target. There is no build step or frontend framework.

## What is here

- Public learning page with a responsive CEFR A1 to C2 overview.
- Supabase email registration, sign-in, email confirmation, password reset, and protected app routes.
- A learner dashboard backed by profiles, lesson progress, quests, achievements, XP, and leaderboard data.
- Twelve seeded lessons across six levels and six skill categories. Objective exercises are scored in PostgreSQL. Writing and speaking prompts save a response and return a rubric, without pretending to evaluate quality automatically.
- TOEFL-style timed practice with server-scored objective questions and score reports. Writing and speaking responses are kept out of the automatic percentage.
- Community threads, replies, reports, and staff moderation.
- Admin content creation and publishing, role management, and member suspension. The first admin must be assigned by the project owner in Supabase.
- Versioned migrations, seed materials, deployment instructions, and security contract tests.

## Run locally

Use Node 18+ for the tests and any static HTTP server for the site:

```sh
python3 -m http.server 8080
```

Open `http://localhost:8080`. Supabase Auth redirects must allow the local verification and password reset URLs before testing email flows. The project URL and browser-safe publishable key are in `js/config.js`; the frontend contains no service-role key.

Run the repository checks with:

```sh
npm test
```

## Supabase setup

Read [the setup guide](docs/setup.md) for the current setup state. The three FluentPath migrations have been applied to project `grlwwmkjwhbxsnnfrovv`, and all six read-only database verification checks passed. See the deployment guide for the remaining production configuration checks.

The migrations are already applied to the configured project. Do not reapply them. For a different project, inspect its migration history and review the SQL before applying changes. The migration files, in order, are:

1. `supabase/migrations/20261028000001_schema.sql`
2. `supabase/migrations/20261028000002_security_and_rpc.sql`
3. `supabase/migrations/20261028000003_seed_curriculum.sql`

The migration files are retained for audit and fresh-project setup.

## Deployment

See [Cloudflare Pages deployment notes](docs/deploy.md). Deploy the repository root as a static site with no build command and `.` as the build output directory. Set the Supabase Auth Site URL and redirect allowlist to match the deployed domain.
