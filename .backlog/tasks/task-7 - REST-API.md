---
id: TASK-7
title: REST API
status: To Do
assignee: []
created_date: '2026-09-15 07:27'
labels:
  - backend
milestone: m-0
dependencies:
  - TASK-6
ordinal: 7000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
api/ routerlari: health, projects CRUD+summary, board, task detail, task create/status/label, sessions (jonli+o'tgan), new session, resume, kill. Xato formati {code, params, detail}.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Board, detail va mutatsiyalar mock clientlar bilan testlangan
- [ ] #2 KanBot o'chiq bo'lsa /sessions 503 kanbot_unavailable, /board esa 200
- [ ] #3 Resume sessiyaning asl cwd'ida; loyihadan tashqaridagi cwd rad etiladi; runner'da yo'q agent rad etiladi
<!-- AC:END -->
