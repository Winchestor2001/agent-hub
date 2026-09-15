---
id: TASK-16
title: Qayta yuklashdan keyingi tekshiruv
status: To Do
assignee: []
created_date: '2026-09-15 07:27'
labels: []
milestone: m-1
dependencies:
  - TASK-15
ordinal: 16000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Yakuniy qabul: reboot'dan keyin terminalsiz ishlashi.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Reboot (yoki logout/login) dan keyin http://127.0.0.1:8700 ishlaydi, runner claude va codex'ni e'lon qiladi, shell yo'q
- [ ] #2 Claude pane'da state_source=hook; Leveling hisoblagichlari to'g'ri
- [ ] #3 Xavfsizlik: begona Origin → 403, lsof faqat 127.0.0.1, auto_approve=false
<!-- AC:END -->
