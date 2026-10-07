---
id: TASK-47
title: Claude multi-account logical sessions and manual handoff in AI Island
status: In Progress
assignee:
  - '@codex'
created_date: '2026-10-07 07:58'
updated_date: '2026-10-07 11:01'
labels: []
dependencies: []
type: feature
ordinal: 54000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Keep two Claude Pro identities isolated while continuing a local project conversation across explicit account handoffs. Preserve the existing native configuration and Codex UI.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Two independently authenticated config directories with no credentials copied or persisted by the manager
- [x] #2 SQLite logical and physical sessions, manual fork handoff, durable locks, git snapshots and history
- [ ] #3 Accounts, project session controls, readiness, usage and safe diagnostics in native UI and island
- [ ] #4 Failure and isolation regression tests pass; real A to B to A continuation verified with two signed-in accounts
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Add native ClaudeSessions library with SQLite, account isolation, capability adapter and sanitized hooks/statusline.
2. Add Terminal runner, process identity and locks; immutable transcript snapshots and explicit fork handoff with git/readiness gates.
3. Integrate Accounts window, session/history/debug UI and island status without replacing existing features.
4. Run isolated failure/isolation tests, native build/regressions and document live two-account acceptance boundary.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-07: swift build OK; swift test 16/16 ikki marta ketma-ket o'tdi (avval testStopLiveProcessWaitsForRunnerAndReleasesLock yiqilardi).
- Tuzatish: LocalClaudeCodeAdapter.identity endi 'ps lstart+comm' emas, proc_pidinfo(PROC_PIDTBSDINFO) bilan pid:start_sec.usec. comm exec paytida o'zgaradi (python shim -> interpreter, launcher -> versiya binari), shuning uchun stopProcess tirik Claude'ni begona deb rad etar va handoff to'xtab qolardi.
- AC#1 dalili: testAccountIsolationAndTwoAccountMaximum (alohida CLAUDE_CONFIG_DIR/CLAUDE_SECURESTORAGE_CONFIG_DIR, API key/OAuth env meros olinmaydi, root 0700), testHookIDDriftAndSecretPayloadAreNotPersisted (SECRET_SENTINEL hech bir jadvalda yo'q), A->B forkda credential-sentinel nusxalanmaydi.
- AC#2 dalili: testLiveFixtureForkAtoBtoAWithHooksAndDirtyGit (SQLite logical/physical, 2 ta completed handoff, git branch/HEAD o'zgarmaydi, locklar bo'shatiladi), testProjectReservationIsDurableAcrossConnections, testOSLockExcludesAnotherOwner, testFailedForkRestoresSourcePointerAndRetainsSnapshot, testStopLiveProcessWaitsForRunnerAndReleasesLock.
- .gitignore'ga macos/AIIslandApp/.build/ qo'shildi; build-ai-island-app.sh dist/ yo'q bo'lsa yaratadi; sh scripts/build-ai-island-app.sh OK.
- Qolgani: AC#3 (native oyna va island UI qo'lda ko'rish) va AC#4 (ikki haqiqiy Claude akkaunt bilan A->B->A) foydalanuvchi login qilishini talab qiladi.
<!-- SECTION:NOTES:END -->
