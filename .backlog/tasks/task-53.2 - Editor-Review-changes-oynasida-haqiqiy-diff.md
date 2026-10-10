---
id: TASK-53.2
title: 'Editor: Review changes oynasida haqiqiy diff'
status: Done
assignee:
  - '@claude'
created_date: '2026-10-10 15:13'
updated_date: '2026-10-10 16:50'
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
- [x] #1 Qoʻshilgan/oʻchirilgan qatorlar soni LCS yoki shunga oʻxshash haqiqiy diff asosida hisoblanadi (boshiga 1 qator qoʻshish = +1/−0)
- [x] #2 Review oynasida oʻzgargan qatorlarning oʻzi (kamida birinchi bir necha hunk, +/− belgilari bilan) koʻrinadi, uzun diff scroll qilinadi
- [x] #3 Unit testlar: boshiga/oʻrtasiga/oxiriga qoʻshish, oʻchirish, almashtirish holatlari
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ClaudeSessions kutubxonasida LineDiff: CollectionDifference (Myers) asosida qator diff, hunks(context:), unifiedText(maxLines:), summary.
2. Review alert: summary (+N/−M) va accessoryView sifatida rangli, scroll qilinadigan unified diff (makeDiffPreview); eski zip asosidagi changeSummary olib tashlanadi.
3. LineDiffTests: boshiga/oʻrtasiga/oxiriga qoʻshish, oʻchirish, almashtirish, hunk ajratish, uzun diff kesilishi.
4. Settings regressiyasi preview matni va scroll'ni tekshiradi; swift test, regressiyalar, release build.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
LineDiff ClaudeSessions targetiga qoʻyildi, chunki unit testlar faqat shu kutubxona uchun bor (ClaudeRateLimits ham shu yerda). Preview: monospace 11pt, + yashil, - qizil, @@ va kesish izohi kulrang, qatorlar oʻralmaydi (gorizontal scroll), 520x260, 400 qatordan keyin '… N more diff lines not shown'. Tekshiruv: LineDiffTests 9/9 (jami swift test 37 ta, 0 xato), settings regressiyasi 104 PASS — preview '+ Regression draft (not saved)' qatorini scroll view ichida koʻrsatadi, render qilingan PNG koʻzdan kechirildi; usage 22/22, accounts 22, release build.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Review changes oynasi endi haqiqiy diff koʻrsatadi. Qoʻshilgan/oʻchirilgan qatorlar Myers (CollectionDifference) asosidagi LineDiff bilan hisoblanadi: boshiga 1 qator qoʻshilsa +1/−0 chiqadi. Alert ichida oʻzgargan qatorlar 3 qator kontekst bilan, hunk sarlavhalari va rangli +/- belgilari bilan scroll qilinadigan koʻrinishda chiqadi. Tekshiruv: 9 ta yangi unit test, settings regressiyasi (preview tekshiruvi va render), usage/accounts regressiyalari, swift test, release build.
<!-- SECTION:FINAL_SUMMARY:END -->
