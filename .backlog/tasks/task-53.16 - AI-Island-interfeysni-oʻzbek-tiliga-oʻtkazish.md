---
id: TASK-53.16
title: 'AI Island: interfeysni oʻzbek tiliga oʻtkazish'
status: To Do
assignee: []
created_date: '2026-10-10 15:13'
labels:
  - ai-island
  - ux
  - i18n
dependencies:
  - TASK-53.4
  - TASK-53.5
  - TASK-53.8
  - TASK-53.9
  - TASK-53.12
  - TASK-53.13
  - TASK-53.14
references:
  - macos/AIIslandApp/Sources/AIIslandApp/main.swift
  - macos/AIIslandApp/Sources/AIIslandApp/ClaudeAccountsWindow.swift
parent_task_id: TASK-53
priority: medium
type: enhancement
ordinal: 76000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
AI Island ning barcha matnlari (island, popover, Settings, editor, Accounts oynasi, alertlar, menyular) inglizcha, loyiha qoidasiga koʻra esa MVP UI faqat oʻzbek tilida (lotin) boʻlishi kerak; rus tili keyinroq (M3). Matnlarni oʻzgartiradigan boshqa subtasklardan keyin bajariladi, ikki marta tarjima qilmaslik uchun.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Foydalanuvchiga koʻrinadigan barcha satrlar oʻzbek tilida (lotin, toʻgʻri oʻ/gʻ belgilari bilan); CLI nomlari va fayl yoʻllari oʻzgarmaydi
- [ ] #2 Satrlar bitta joyda (Localizable.strings/String Catalog yoki yagona lugʻat) saqlanadi, keyinchalik rus tili qoʻshish mumkin
- [ ] #3 Oʻzbekcha uzunroq matnlar island, popover va kartalarda kesilmaydi (skrinshot bilan tasdiqlangan)
- [ ] #4 Regressiya testlaridagi matn tekshiruvlari yangilanadi va barchasi oʻtadi
<!-- AC:END -->
