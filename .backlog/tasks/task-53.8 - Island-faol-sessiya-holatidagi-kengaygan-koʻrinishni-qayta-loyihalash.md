---
id: TASK-53.8
title: 'Island: faol sessiya holatidagi kengaygan koʻrinishni qayta loyihalash'
status: To Do
assignee: []
created_date: '2026-10-10 15:13'
labels:
  - ai-island
  - ux
dependencies: []
references:
  - macos/AIIslandApp/Sources/AIIslandApp/main.swift
  - macos/AIIslandApp/Sources/AIIslandApp/ClaudeAccountsWindow.swift
parent_task_id: TASK-53
priority: medium
type: enhancement
ordinal: 68000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Faol Claude sessiyasi boʻlsa island 58px dan 280px gacha sakrab kengayadi va qora notch ichiga oddiy tizim `NSButton` ("Accounts / Continue →") qoʻyiladi. Bu stilga mos emas, matn esa oʻralib ketadi. Kengayish keskin, animatsiyasiz.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Kengaygan holat island stiliga mos (qora fon, maxsus tugma/link uslubi, tizim bezelsiz)
- [ ] #2 Holat almashuvi animatsiya bilan (Reduce Motion da animatsiyasiz) va yuqori markaz atrofida
- [ ] #3 Matn bir qatorda sigʻadi yoki mazmunli qisqartiriladi; tugma faqat amal mavjud boʻlganda (limit yaqin/tugagan, boshqa akkaunt tayyor) koʻrinadi
- [ ] #4 Accounts regressiyasidagi island kengligi tekshiruvi yangilanadi
<!-- AC:END -->
