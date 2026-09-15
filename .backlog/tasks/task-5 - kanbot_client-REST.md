---
id: TASK-5
title: kanbot_client (REST)
status: To Do
assignee: []
created_date: '2026-09-15 07:27'
labels:
  - backend
milestone: m-0
dependencies:
  - TASK-2
  - TASK-3
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
KanBot'ga yagona kirish nuqtasi: httpx.AsyncClient, pydantic modellar (extra=ignore), typed xatolar, versiya tekshiruvi, argv'dan --settings JSON'ni tozalash.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 health, runners, list_panes, get_pane, start_pane, read_pane, send_text, send_keys, kill_pane, remove_pane, list_agent_sessions — respx testlari (refused, 409, 502)
- [ ] #2 Noma'lum maydonlar e'tiborsiz; 0.8.x bo'lmagan versiyada ogohlantirish
- [ ] #3 argv'dan --settings qiymati olib tashlanadi
<!-- AC:END -->
