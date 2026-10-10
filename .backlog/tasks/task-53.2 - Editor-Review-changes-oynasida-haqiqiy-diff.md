---
id: TASK-53.2
title: 'Editor: Review changes oynasida haqiqiy diff'
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
priority: high
type: bug
ordinal: 62000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`changeSummary` qatorlarni pozitsiya boʻyicha (`zip`) solishtiradi: fayl boshiga bitta qator qoʻshilsa "+4/−3" kabi notoʻgʻri son chiqadi. Saqlashdan oldingi koʻrib chiqish bosqichi shu sababli foydalanuvchiga soxta xavfsizlik tuygʻusi beradi.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Qoʻshilgan/oʻchirilgan qatorlar soni LCS yoki shunga oʻxshash haqiqiy diff asosida hisoblanadi (boshiga 1 qator qoʻshish = +1/−0)
- [ ] #2 Review oynasida oʻzgargan qatorlarning oʻzi (kamida birinchi bir necha hunk, +/− belgilari bilan) koʻrinadi, uzun diff scroll qilinadi
- [ ] #3 Unit testlar: boshiga/oʻrtasiga/oxiriga qoʻshish, oʻchirish, almashtirish holatlari
<!-- AC:END -->
