---
id: TASK-6
title: Domen servislari
status: To Do
assignee: []
created_date: '2026-09-15 07:27'
labels:
  - backend
milestone: m-0
dependencies:
  - TASK-4
  - TASK-5
ordinal: 6000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
linking (task_prefix asosida ID, argv --resume orqali sessiya bog'lash), loyihaga tegishlilik (realpath), summary hisoblagichlari, effective_state (soxta blocked'ni filtrlash), sessiya prompt prefiksi.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Prompt prefiksi talabdagi rus tilidagi matn bilan bayt-bayt mos
- [ ] #2 ID bog'lash prefiksga asoslangan: UTF-8 bog'lanmaydi, task-1 == TASK-001
- [ ] #3 cwd realpath orqali loyiha papkalariga tegishliligi aniqlanadi; summary hisoblagichlari (status, bug, sessiyalar, blocked) fixture'larga mos
- [ ] #4 effective_state: idle notification blocked deb ko'rsatilmaydi; codex holati ≈ belgili
<!-- AC:END -->
