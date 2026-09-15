---
id: TASK-3
title: 'Sozlamalar, loyihalar registri, Agent Hub himoyasi'
status: To Do
assignee: []
created_date: '2026-09-15 07:27'
labels:
  - backend
milestone: m-0
dependencies:
  - TASK-1
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
settings.py (host 127.0.0.1, port, kanbot_url), registry.py (~/.config/agent-hub/projects.yaml, atomar yozish), security.py (Host/Origin middleware HTTP va WS uchun).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 projects.yaml yo'q bo'lsa Leveling (~/my-projects/leveling-backend) bilan yaratiladi; saqlash atomar
- [ ] #2 repos bo'sh bo'lsa [backlog_dir]; noto'g'ri yo'l — path_invalid, bekloqsiz papka — backlog_not_found
- [ ] #3 Begona Host yoki Origin Agent Hub'da HTTP va WS uchun 403 oladi; testlar bor
<!-- AC:END -->
