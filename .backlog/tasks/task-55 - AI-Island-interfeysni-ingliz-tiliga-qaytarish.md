---
id: TASK-55
title: 'AI Island: interfeysni ingliz tiliga qaytarish'
status: Done
assignee:
  - '@claude'
created_date: '2026-10-11 07:49'
updated_date: '2026-10-11 08:00'
labels:
  - ai-island
dependencies: []
priority: medium
type: enhancement
ordinal: 78000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-53.16 da AI Island interfeysi oʻzbek tiliga oʻtkazilgan edi (Language.current = .uzbek). Foydalanuvchi dastur interfeysi ingliz tilida boʻlishi kerakligini aytdi (2026-10-11). Oʻzbekcha lugʻat kodda qoladi, keyin kerak boʻlsa qaytarish yoki til tanlovini qoʻshish uchun.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 AI Island barcha oynalari (orol, popover, Settings, muharrir, Accounts) va Update skripti inglizcha matn koʻrsatadi; sana formatlari en_US
- [x] #2 Oʻzbekcha lugʻat oʻchirilmaydi; swift test va uchala regressiya oʻtadi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Language.current = .english.
2. swift test, uchala regressiya, release build, ilovani qayta ochish va skrinshot bilan tekshirish.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Language.current = .english. Testlar joriy til oʻzbekcha deb yozilgan edi (45 ta xato): ResetCountdown va ConfigurationSyntax testlari inglizcha matnni kutadigan qilindi, oʻzbekcha lugʻat esa Localization testlarida toʻgʻridan-toʻgʻri tekshiriladi (Localization.uzbek["Settings"] == "Sozlamalar"). Usage regressiyasidagi caption-wrap tekshiruvi tilga bogʻliq emas: matn bir qatorga sigʻmasagina ikkinchi qator kutiladi, kesilmaslik har doim tekshiriladi. swift test 60/60; accounts 36, usage 52, settings 103 PASS. Regressiya rasmlari: popover ('Live AI limits', '5H · 40% used · resets in 2h 15m'), Accounts ('Claude Accounts', 'Oct 11, 2026 at 12:58 PM') inglizcha. Release build qayta ochildi.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
AI Island interfeysi yana ingliz tilida (Language.current = .english); oʻzbekcha lugʻat kodda qoldi. Til taxminiga bogʻliq testlar tildan mustaqil qilindi. swift test 60/60, uchala regressiya PASS, popover va Accounts rasmlari bilan tekshirildi.
<!-- SECTION:FINAL_SUMMARY:END -->
