---
id: TASK-53.8
title: 'Island: faol sessiya holatidagi kengaygan koʻrinishni qayta loyihalash'
status: Done
assignee:
  - '@claude'
created_date: '2026-10-10 15:13'
updated_date: '2026-10-10 17:57'
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
- [x] #1 Kengaygan holat island stiliga mos (qora fon, maxsus tugma/link uslubi, tizim bezelsiz)
- [x] #2 Holat almashuvi animatsiya bilan (Reduce Motion da animatsiyasiz) va yuqori markaz atrofida
- [x] #3 Matn bir qatorda sigʻadi yoki mazmunli qisqartiriladi; tugma faqat amal mavjud boʻlganda (limit yaqin/tugagan, boshqa akkaunt tayyor) koʻrinadi
- [x] #4 Accounts regressiyasidagi island kengligi tekshiruvi yangilanadi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ClaudeAccountsWindow.islandStatus: tuzilmali holat (akkaunt, foiz, stale, tayyor boshqa akkaunt, restored). limitReached, nearLimit (UsageLevel.critical, ≥90%) va canContinue = nearLimit && standby. islandSummary shu holatdan quriladi (matn oʻzgarmaydi).
2. Kengaygan island: chap ustun yigʻilgan holat bilan bir xil (58px, Codex/Claude kataklari). Oʻngda akkaunt nomi (12pt, bir qator, truncating) va holat satri ('96% used', 'Limit reached', 'Usage unknown', daraja rangida). Tizim NSButton oʻrniga bezelsiz pill 'Continue with X →' faqat canContinue boʻlganda. Toʻliq matn tooltip'da.
3. Kenglik 280 → 232. Kengayish/torayish yuqori markaz atrofida, NSAnimationContext bilan 0.22 s; Reduce Motion yoqilgan boʻlsa animatsiyasiz. Ilova ishga tushganda animatsiya yoʻq.
4. Accounts regressiyasi: kenglik 232, bezelsiz tugma faqat amal bor holatda (96% + tayyor B, 100%), past usage va B signed out holatida tugma yoʻq, matn bir qator, animatsiyali kengayish yuqori markazni saqlaydi; island rasmi.
5. swift test, uchala regressiya, release build va skrinshot.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Kengaygan island: chapda 58px ustun (Codex/Claude kataklari), oʻngda akkaunt nomi va holat satri (bir qator, truncating). Tizim NSButton oʻrniga bezelsiz toʻq sariq pill 'Continue with X →', u faqat canContinue (≥90% yoki limit tugagan + boshqa akkaunt tayyor) boʻlganda chiqadi. Kenglik 280 → 232. Kengayish NSAnimationContext bilan 0.22 s, Reduce Motion yoqilganda va ishga tushishda animatsiyasiz.
Topilgan xatolar: (1) windowDidMove kengaygan origin'ni saqlardi va qayta ochilganda island 58px freymga notoʻgʻri tiklanardi; endi yigʻilgan origin yuqori markaz boʻyicha saqlanadi. (2) Tafsilotlarning trailing cheklovi required edi (2+12pt), shu sabab 58px oyna 72px gacha kengayib, markaz 7pt surilardi; prioriteti windowSizeStayPut dan pastga tushirildi.
Tekshiruv: swift test 52/52; settings 104, usage 29, accounts 30 PASS (yangi: 232 kenglik, bir qatorli matn island ichida, pill 96%+B tayyor va 100% da bor, 40% va B signed out holatida yoʻq, kontent oynani kengaytirmaydi, animatsiya yuqori markazni saqlaydi, accounts.island.png koʻzdan kechirildi). ~/.claude/settings.json va ~/.codex/config.toml shasum oʻzgarmadi. Release build ishga tushirildi, haqiqiy skrinshot: faol sessiyasiz 58×126.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Faol sessiya holatidagi kengaygan island island uslubida qayta qurildi: akkaunt nomi va daraja rangidagi holat satri, tizim tugmasi oʻrniga bezelsiz 'Continue with X →' pill. Pill faqat amal mavjud boʻlganda chiqadi. Kenglik 232px, oʻtish yuqori markaz atrofida animatsiya bilan (Reduce Motion da animatsiyasiz). Saqlangan pozitsiya va Auto Layout sabab markaz siljishi tuzatildi. swift test, uchala regressiya (accounts 30 PASS), release build va skrinshot bilan tekshirildi.
<!-- SECTION:FINAL_SUMMARY:END -->
