---
id: TASK-53.13
title: 'Accounts oynasi: diagnostikani yigʻish va amalga yaqin xabarlar'
status: To Do
assignee: []
created_date: '2026-10-10 15:13'
labels:
  - ai-island
  - ux
dependencies: []
references:
  - macos/AIIslandApp/Sources/AIIslandApp/ClaudeAccountsWindow.swift
parent_task_id: TASK-53
priority: low
type: enhancement
ordinal: 73000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Claude Accounts & Sessions oynasida "Handoff history" va "Developer diagnostics" (CLAUDE_CONFIG_DIR, session ID, PID va h.k.) har doim ochiq turadi va 220px joy egallaydi — bu oddiy foydalanuvchi uchun ichki maʼlumot. Xato va holat xabarlari bitta umumiy qatorda, bosilgan tugmadan uzoqda chiqadi.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Diagnostika va tarix yigʻiladigan (disclosure) boʻlimda, standart holatda yopiq; holat oynalar orasida eslab qolinadi
- [ ] #2 Amal natijasi/xatosi tegishli akkaunt yoki sessiya kartasida (yoki uning yonida) koʻrinadi
- [ ] #3 Accounts regressiyasi (history va diagnostics mavjudligi) yangilanadi va oʻtadi
<!-- AC:END -->
