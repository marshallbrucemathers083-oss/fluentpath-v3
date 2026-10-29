# Admin layout verification

The admin content rows previously inherited the learner grid `38px minmax(0, 1fr) auto`. Admin rows have only details and actions, so the title occupied the 38px marker column. Global overflow wrapping exposed the mismatch as vertical text. Admin rows now use their own two-column grid; panels at or below 460px stack details above actions. Member controls use the same panel-width breakpoint. Student row styles are unchanged.

## Reproduce without changing production data

1. Open the project root with VS Code Live Server. Sign in with an existing authorized administrator and open `app.html#/admin`. Use a staging account/environment for any functional write checks.
2. In browser responsive mode, test widths **360, 390, 768, 1024, 1440, and 1792px** at 100% zoom. Scroll through the entire desk at each width.
3. Inspect Learning content with a long title such as “Designing accountable consultation”. If needed, change text only in browser DevTools; do not save edits through the app. Confirm titles use full words, metadata remains underneath, and Manage/Unpublish sit either to the right or together below the details. Check both Published and Draft labels.
4. Change a member's displayed email in DevTools to `averylong.account.name.for.responsive.testing@example-university.edu`. Confirm it wraps within the information area and does not overlap the role selector or suspension button. Verify administrator controls remain disabled. Tab through enabled controls and check visible focus.
5. Open Add lesson and Manage, without submitting. Check long headings, all labels, textarea resizing, dropdowns, close buttons, and Escape. At 200% zoom, confirm controls remain reachable by scrolling.
6. Inspect populated reports, warnings, restrictions, practice-management forms, and expanded moderation history. Confirm long reasons and JSON wrap within their panels. Inspect empty states on a staging dataset or change only the displayed DOM locally.
7. Run `document.documentElement.scrollWidth <= document.documentElement.clientWidth` in DevTools at each width. Expected: `true`. Check visually as well; this alone cannot detect clipped content.

Actual verification for this change: source inspection, test suite, production build, and whitespace checks. Authenticated rendered views, mouse/touch operation, and the six viewport widths remain unverified. No production records were changed for testing.
