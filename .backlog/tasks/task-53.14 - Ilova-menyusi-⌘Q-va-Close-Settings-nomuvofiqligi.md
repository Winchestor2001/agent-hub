---
id: TASK-53.14
title: 'Ilova menyusi: ⌘Q va "Close Settings" nomuvofiqligi'
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
priority: low
type: bug
ordinal: 74000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Asosiy menyuda "Close Settings" ⌘Q ga bogʻlangan va `NSApplication.terminate` ni chaqiradi. Settings ochiq boʻlsa oyna yashiriladi, ochiq boʻlmasa butun ilova yopiladi — nom va xatti-harakat mos emas. Oynani yopish uchun standart ⌘W ham yoʻq.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ⌘W joriy Settings/editor/Accounts oynasini yopadi
- [ ] #2 Menyu bandlari nomi haqiqiy amalga mos (masalan, "Quit AI Island" ⌘Q, "Close Window" ⌘W); ⌘Q xatti-harakati hujjatlashtiriladi
- [ ] #3 Settings regressiyasidagi ⌘Q tekshiruvi yangi xatti-harakatga moslashtiriladi
<!-- AC:END -->
