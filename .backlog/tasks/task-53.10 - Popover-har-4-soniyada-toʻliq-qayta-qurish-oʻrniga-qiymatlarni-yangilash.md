---
id: TASK-53.10
title: 'Popover: har 4 soniyada toʻliq qayta qurish oʻrniga qiymatlarni yangilash'
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
ordinal: 70000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`rebuildUsageViews` va `refreshClaudeAuth` har yangilanishda popoverning `contentViewController`ini butunlay almashtiradi. Bu tooltip, hover, VoiceOver fokusini yoʻqotadi va miltillashi mumkin; island `rebuildNotchContent` ham har safar barcha subviewlarni qayta yaratadi.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Popover va island koʻrinishlari bir marta quriladi, yangilanishda faqat matn/progress/rang qiymatlari oʻzgaradi (tuzilma oʻzgarsa — masalan akkaunt qoʻshilsa — qayta qurish mumkin)
- [ ] #2 Popover ochiq paytda tooltip va tugma hover holati yangilanishdan keyin saqlanadi
- [ ] #3 Qiymat oʻzgarmasa koʻrinish umuman qayta chizilmaydi
- [ ] #4 Usage regressiyasi oʻtadi
<!-- AC:END -->
