---
id: TASK-43
title: 'AI Island: Skills va Agents oynasini qayta ochishdagi crash'
status: Done
assignee:
  - '@codex'
created_date: '2026-09-30 18:26'
updated_date: '2026-09-30 18:30'
labels: []
dependencies: []
type: bug
ordinal: 50000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Konfiguratsiya oynasi yopilgandan keyin Skills yoki Agents kartasi bosilganda EXC_BAD_ACCESS yuz beradi. Crash manzili saqlangan konfiguratsiya oynasini retain qilishga togrilangan.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Settings va konfiguratsiya oynalari yopilib qayta ochilganda app ishlashda davom etadi
- [x] #2 Codex va Claude barcha kategoriyalari close/reopen regression sinovidan otadi
- [x] #3 Skills kartasidagi fayl soni editor royxatiga mos keladi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Crash manzilini disassembly bilan tekshirish. 2. Oyna close/reopen regression sinovida eski crashni takrorlash. 3. Oyna ownershipini tuzatish va shu sinovni qayta ishga tushirish. 4. Yangilangan appni ishga tushirish.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Crash offset 0x10830 resolves to retaining configurationWindow before setTitle, not sender.identifier. Pre-fix native close/reopen regression reproduced SIGSEGV at configurationWindow.isVisible after performClose (AIIsland-2026-09-30-232615.ips). Set isReleasedWhenClosed=false on both retained windows. Added opt-in --settings-regression-report native runner. Post-fix report /private/tmp/ai-island-regression-after.txt passes 36 category opens across both providers, Settings close/reopen and Command-Q/reopen, with file counts matching lists. Stopped three stale app instances and launched one updated instance (PID 21144).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Fixed dangling NSWindow references after close. Release build passed. Native regression reproduced the old crash, then passed all 36 category open/close cycles plus Settings and Command-Q checks after fix. Updated app is running as one instance.
<!-- SECTION:FINAL_SUMMARY:END -->
