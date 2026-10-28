# FluentPath V3 local review

No remote writes, migration application, database reset, push, or deployment were performed.

## Scoring findings

Read-only inspection of project grlwwmkjwhbxsnnfrovv found twelve starter lessons with consistent objective keys, the expected UUID-based submit_exercise implementation, and zero persisted objective attempts. The reported universally incorrect marking is therefore **not reproduced**. There is no separate challenge implementation in this checkout; daily quests are advanced by exercise RPCs.

Confirmed defects addressed locally:

- Lesson choices could change while a submitted choice was being checked, associating feedback with a different visible selection. Controls now lock during submission.
- Concurrent TOEFL saves could overwrite newer selections. Saves now execute in order. Failed saves previously appeared successful and allowed finishing; errors now prevent finishing until retried.
- Concurrent exercise submissions could count daily quest activity more than once. RPCs now serialize through the learner profile row before checking activity.
- Perfect-practice achievements could follow incorrect attempts or ungraded writing. The new check excludes both cases.
- Admin exercise creation could leave an exercise without options after a failed second request. One transactional RPC now creates both.
- A banned user could bypass the initial application screen using hash navigation. Route changes now recheck profile restrictions; temporary suspensions also block server submission and community RPCs.
- Lesson completion awarded a fixed 20 XP regardless of the lesson's configured reward. The new scoring migration uses `lessons.xp_reward`.

No correct-answer keys are added to student payloads. Feedback parsing rejects malformed server scores instead of inventing a result.

## Exact pending migrations

1. `20261028000004_submission_and_moderation.sql`: serialized scoring, restriction checks, suspension dates, duplicate-open-report prevention, own-report visibility, moderation actions and audit history.
2. `20261028000005_scenario_curriculum.sql`: 36 additive scenario lessons with 48 objective exercises and 12 writing/speaking responses; 12 additional unofficial practice questions, including three ungraded written responses. The six scenarios progress from familiar routines to critical analysis. The versioned generator is `scripts/build-curriculum.py`. Existing lesson IDs and progress are untouched.
3. `20261028000006_admin_content.sql`: transactional administrator content editor, lesson archival metadata, stricter content RLS, and validation of objective options. Exercises must be unpublished before editing; exam question edits are rejected during active attempts.
4. `20261028000007_admin_workflows.sql`: exact platform totals, creation and publishing of draft unofficial practice sets, question creation, private report context, administrator-only report actions, direct exercise/key write revocation, and an archive/publish consistency trigger. Used exam content must be replaced with a new set rather than edited.

## Risks and verification

These migrations have not been executed. Review SQL and test in an isolated database first. A partial unique index deliberately fails rather than deleting existing duplicate open reports; inspect for duplicates before application. New admin UI requires migrations 4 and 6. New lesson and practice data become visible after migration 5. Exercise options retain their IDs by position; changing an answer key can change the interpretation of historical selections, so archive and replace substantially revised lessons. Existing attempts retain their stored grades.

Run all seven migrations only in a fresh disposable test project, then run `supabase/regression.sql`. It creates test accounts inside a transaction, exercises every published objective option, checks idempotent XP and written practice, scores all-correct and all-incorrect exams, checks student key isolation, signup privilege escalation, moderation denial, suspension enforcement, restore/ban actions, duplicate reports, and audit persistence, then rolls back. Do not run it against production. Broader suspension-expiry, report-privacy, concurrent-client, and responsive browser tests remain required before release.

`npm test` passes all five test files. `node --test --test-isolation=none --test-reporter=spec` reports 24 passing tests, including the actual lesson event handler evaluated with lightweight control doubles and controlled RPC responses: four objective types, written practice, mid-request selection changes, and request failure recovery. Other runtime tests cover ordered saves and score parsing. These tests do not execute PostgreSQL or replace browser tests. Syntax checks pass for all changed JS modules.

Docker access was denied. An attempt to install an embedded PostgreSQL test dependency into `/tmp` failed with DNS error EAI_AGAIN; no runtime dependency was added to the app. A local HTTP server could not start because the sandbox denied socket creation. A direct file-based admin editor preview was also attempted; Firefox exited with code 139 before producing a screenshot. Authenticated browser click-through, mobile screenshots, and live RPC submission were not completed. No production test credentials were used. A fresh read-only remote check again found zero objective attempts and zero stored key mismatches.

Cloudflare Pages remains a static HTML/CSS/ES-module application; no server build or new runtime dependency was introduced. Existing headers and redirects remain applicable, but deployment has not been tested.

## Rollback plan

Each migration is transactional: errors roll back that file. Take a Supabase backup before approved production application. For a post-commit rollback, revert local application code, restore the prior definitions of changed functions and policies from migration 2, and retain new curriculum and audit rows unpublished rather than deleting user-linked content. Do not re-run migration 2 itself. Prepare and review a targeted compensating migration based on actual production state. Retain suspension and audit information until access-policy consequences have been reviewed.

## Remaining work

The main marking complaint still needs reproduction with an affected lesson and a submitted RPC response. Full security and visual delivery gates remain pending database execution and browser testing. The content editor now uses labeled fields, choice controls, and feedback fields. Administrators can create draft practice sets and questions, publish/unpublish sets, inspect report context and prior warnings, remove/hide/restore content, and select a reported author for account review. Own-account moderator warnings are shown in the community view. Existing workflows refresh the workbench after actions. Platform statistics use administrator-only aggregate queries rather than treating the capped roster as a total. No claim of production readiness is made.

Anti-Slop gate evidence: automated checks PASS (`npm test` and JavaScript syntax checks); source motion review PASS (short feedback/reveal transitions, reduced-motion checks, finite skeleton animation); full visual/accessibility delivery gate NOT VERIFIED because authenticated browser and responsive checks were unavailable. This is an incomplete local development checkpoint, not a passed release gate.
