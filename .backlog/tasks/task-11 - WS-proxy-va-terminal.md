---
id: TASK-11
title: WS proxy va terminal
status: To Do
assignee: []
created_date: '2026-09-15 07:27'
labels:
  - client
  - backend
milestone: m-0
dependencies:
  - TASK-10
ordinal: 11000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Backend WS /ws/panes/{id} → KanBot /ws/web proxy (upstream doim o'qiladi, 2 MB navbat). Frontend TerminalView (xterm.js lokal bundle) markaz o'rnida, tezkor tugmalar bilan.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Terminal markaziy panel o'rnida ochiladi, Doskaga qaytish tugmasi bor; yozish pane'ga yetadi
- [ ] #2 Tezkor tugmalar Enter, y, n, Esc, Ctrl-C ishlaydi
- [ ] #3 replay terminalni tozalaydi; ikkinchi tab birinchisini buzmaydi
- [ ] #4 Test: to'xtab qolgan mijoz upstream'ni bloklamasdan uziladi
<!-- AC:END -->
