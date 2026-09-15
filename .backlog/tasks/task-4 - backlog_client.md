---
id: TASK-4
title: backlog_client
status: To Do
assignee: []
created_date: '2026-09-15 07:27'
labels:
  - backend
milestone: m-0
dependencies:
  - TASK-3
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Backlog.md CLI'ga yagona kirish nuqtasi: subprocess (cwd, BACKLOG_CWD, stdin=DEVNULL, NO_COLOR=1, timeout), --json parsing, typed xatolar, fingerprint kesh, DoD uchun task view keshi (≤4 parallel), single-flight.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 list_tasks, view_task, statuses, labels, milestones (id→nom), task_prefix, create_task, set_status, add_label — haqiqiy chiqish fixture'lari bilan testlangan
- [ ] #2 Ota-papkadagi bekloq, timeout va lock xatolari BacklogNotFound/BacklogCliError/BacklogLocked ga aylanadi (lock'da 1 marta qayta urinish)
- [ ] #3 Fayllar o'zgarmasa kesh subprocess chaqirmaydi
- [ ] #4 pytest -m integration vaqtinchalik papkada haqiqiy backlog bilan init/create/edit/list ni tekshiradi
<!-- AC:END -->
