# Local and Supabase setup

## Supabase project

The client is configured for `https://grlwwmkjwhbxsnnfrovv.supabase.co` and uses the project's publishable `sb_publishable_…` key. A publishable key is intended for browsers. Never paste a secret or `service_role` key into `js/config.js`.

The three FluentPath migrations have been applied to project `grlwwmkjwhbxsnnfrovv`, and the six read-only checks in `supabase/verify.sql` passed. Do not reapply them to this project. Review Supabase Auth URL settings in the project dashboard before testing registration or password recovery on a new origin.

For a different Supabase project, inspect its migration history and current objects first. Remote database changes require explicit approval. If approved, apply each migration to that target project one at a time in filename order, verify success before proceeding, then run `supabase/verify.sql` and review the project's Database Advisors.

Do not run only the schema migration and leave the project in that state. It intentionally has RLS enabled with no policies until migration 2 is applied. Running these files changes the database and requires explicit approval first.

In Supabase Auth settings, set the Site URL to the local development URL and add these redirect URLs:

- `http://localhost:8080/verify-email.html`
- `http://localhost:8080/reset-password.html`
- The matching HTTPS URLs for your deployed domain.

Email confirmation should remain enabled for production use. A newly registered account starts with the `student` role. The auth trigger creates the private profile row.

## First administrator

Follow `docs/release-checklist.md` and the guarded operator-only `supabase/admin-bootstrap.sql` template after the pending release succeeds. The owner must explicitly approve one verified UUID/email pair. Do not promote by an email-only UPDATE or through signup metadata. No account has been promoted.

## Local static server

```sh
python3 -m http.server 8080
```

The app uses browser ES modules and the Supabase JS v2 CDN ESM entry, so serve over HTTP instead of opening `file://` URLs. If a network filter blocks jsDelivr, the Supabase client module will not load.

## Security notes

- `exercise_options` and TOEFL answer options have no learner read policy. RPCs return only option IDs and visible text.
- Exercise answers are checked by `submit_exercise`; lesson completion, XP, quests, streaks, and achievements are updated in one database transaction.
- TOEFL answers are saved to an owned attempt and the database calculates the score when the attempt is finished. The browser cannot submit a score or XP value.
- Profile role, XP, ban status, and email are never editable through the public profile RPC. Community and leaderboard views omit email.
- Forum posting, reporting, and moderation use authenticated RPCs and server-side role checks.
- Private content is not returned until a lesson is published. A database trigger blocks publication until the notes and exercises have valid content.
- Supabase RLS is the authorization boundary. The static frontend is not a trusted server.

## What requires a server outside this stack

Written and spoken responses are retained as practice and receive a rubric, but this version does not claim automated language-quality grading. Add a vetted server-side evaluator only if that product behavior is needed. Never put evaluator credentials in the browser.
