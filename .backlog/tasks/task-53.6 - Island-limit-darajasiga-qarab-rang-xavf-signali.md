---
id: TASK-53.6
title: 'Island: limit darajasiga qarab rang (xavf signali)'
status: To Do
assignee: []
created_date: '2026-10-10 15:13'
labels:
  - ai-island
  - ux
dependencies: []
references:
  - macos/AIIslandApp/Sources/AIIslandApp/main.swift
parent_task_id: TASK-53
priority: medium
type: enhancement
ordinal: 66000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Hozir halqa va chiziq rangi faqat provayderni bildiradi: 12% ham, 96% ham bir xil toʻq sariq. Island ning asosiy vazifasi limitga yaqinlikni bir qarashda koʻrsatish, shuning uchun xavf darajasi rang bilan ham (va rangga bogʻliq boʻlmagan belgi bilan ham) bildirilishi kerak.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Chegaralar: <70% oddiy provayder rangi, 70–89% ogohlantirish (sariq), ≥90% xavf (qizil); qiymatlar bitta joyda konstanta sifatida
- [ ] #2 Island halqasi, ostidagi chiziq va popover progress barlari bir xil qoidani ishlatadi
- [ ] #3 ≥90% holatda rangdan tashqari ham signal bor (masalan, ogohlantirish belgisi yoki yumshoq pulsatsiya), Reduce Motion yoqilgan boʻlsa animatsiya oʻchadi
- [ ] #4 Regressiya: 50/80/95% uchun kutilgan ranglar
<!-- AC:END -->
