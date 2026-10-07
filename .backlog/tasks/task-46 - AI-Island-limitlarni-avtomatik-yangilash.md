---
id: TASK-46
title: 'AI Island: limitlarni avtomatik yangilash'
status: Done
assignee:
  - '@codex'
created_date: '2026-10-05 06:22'
updated_date: '2026-10-05 06:28'
labels: []
dependencies: []
type: bug
ordinal: 53000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Limitlar hozir faqat island/card refresh bosilganda yangilanadi; foydalanuvchi 3-5 soniyada avtomatik yangilanishni so‘radi.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Limitlar card yopiq yoki ochiq bo‘lsa ham har 4 soniyada avtomatik so‘raladi va UI yangilanadi.
- [x] #2 Parallel refresh so‘rovlari ustma-ust tushmaydi va vaqtinchalik xatoda oxirgi limit saqlanadi.
- [x] #3 Native regression tekshiruvi va macOS release build muvaffaqiyatli; yangilangan app qayta ochiladi.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Add a retained 4-second timer in common run-loop modes for Codex usage, independent of popover visibility. 2. Guard in-flight requests and preserve the last successful snapshot on errors. 3. Exercise real timer and native compact/popover rendering using deterministic regression snapshots; build and reopen release app.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Added a 4-second timer in common run-loop modes, invalidated at termination. In-flight guard prevents duplicate Codex requests; nil responses retain the last successful usage. Claude currently exposes configuration/auth status rather than usage limits, so its auth command is not polled every 4 seconds. Native deterministic regression report /private/tmp/ai-island-usage-regression-20261005-v2.txt: 10 PASS, 0 FAIL, including closed/open popover, actual ring/caption updates, 3-5 second cadence, overlap and failure recovery. Release build completed in 5.20s. Restarted dist/AI Island.app: PID 2660; automatic real Codex app-server requests observed as PIDs 2741 and 2764 without manual refresh.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Fixed automatic Codex limit refresh every 4 seconds with overlap protection and preservation of the last successful value. Native regression: 10/10 PASS; release build passed; rebuilt app reopened and recurring real account-read processes observed.
<!-- SECTION:FINAL_SUMMARY:END -->
