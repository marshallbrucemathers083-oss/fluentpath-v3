# Cloudflare Pages deployment checklist

No deployment or Git push has been performed. Use `docs/release-checklist.md` as the release authority; database and authenticated browser verification are still required.

1. Run `npm test` and `npm run build`. The build output is **`dist`**. Do not publish `.`: the repository contains SQL answer keys and operator scripts.
2. For Pages Git integration, use build command `npm run build` and output directory `dist`; no framework is required. For dashboard Direct Upload, upload only the contents of the locally built `dist/`. Publishing/uploading requires owner approval. Do not initialize/push a repository just to bypass that approval.
3. The artifact contains HTML, CSS, browser ES modules, `_headers`, `_redirects`, and a generated 404 page. Friendly auth/app routes are defined in `_redirects`; hash navigation is handled in `app.html`.
4. Verify `js/config.js` targets `https://grlwwmkjwhbxsnnfrovv.supabase.co` and contains only a publishable key. No service-role, database password or admin bootstrap credentials belong in Pages variables or frontend code. Keep the source repository private if it contains curriculum answer keys.
5. In the Supabase Auth dashboard, set Site URL to the final HTTPS site origin, and explicitly allow `https://YOUR-DOMAIN/verify-email.html` and `https://YOUR-DOMAIN/reset-password.html`. Add a specific approved preview origin only when testing it. Local callback allowlisting is optional and does not replace the production Site URL. Keep email confirmation enabled and confirm email delivery/SMTP limits work before judging.
6. Apply only the approved release bundles and bootstrap procedure described in `release-checklist.md`; the original three migrations are already applied. Do not deploy a database-dependent admin application against a partial migration chain.
7. Check `/`, `/login`, `/register`, `/app`, confirmation/reset callbacks and an unknown path. Verify `/supabase/migrations/...`, `/docs/...`, `/.env` and `/tests/...` expose no source files. Confirm Pages actually returns security headers and HTTPS; the static build does not emulate Pages routing/headers.
8. Run the student/admin smoke list in `release-checklist.md`, including two-account report privacy, restrictions, persistence and mobile keyboard/menu behavior. Check the browser console and jsDelivr/Supabase/font network requests; the app depends on the Supabase CDN module being reachable. Do not claim that a successful upload proves these workflows.
9. Retain the previous approved artifact and the database backup. For an incident, keep maintenance mode and use the reviewed containment plan; do not reset the database or delete user progress.

No runtime server or build dependency installation is needed for this vanilla stack. The generated artifact and source tests pass locally; Pages hosting, Auth dashboard URL configuration, authenticated flows and mobile browser checks remain unverified.
