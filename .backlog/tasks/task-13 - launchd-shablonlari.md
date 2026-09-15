---
id: TASK-13
title: launchd shablonlari
status: To Do
assignee: []
created_date: '2026-09-15 07:27'
labels:
  - backend
milestone: m-1
dependencies:
  - TASK-12
ordinal: 13000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
3 ta plist shabloni: kanbot-server (himoya launcher'i), kanbot-runner (--safe), backend. PATH, ProcessType, WorkingDirectory, loglar.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Render qilingan plist'lar plutil -lint dan o'tadi
- [ ] #2 PATH real papkalarni o'z ichiga oladi; RunAtLoad, KeepAlive, ThrottleInterval; loglar ~/Library/Logs/agent-hub/
- [ ] #3 runner --safe bilan; plist'larda API kalitlar yoki tokenlar yo'q
<!-- AC:END -->
