---
id: TASK-53.6
title: 'Island: limit darajasiga qarab rang (xavf signali)'
status: Done
assignee:
  - '@claude'
created_date: '2026-10-10 15:13'
updated_date: '2026-10-10 17:18'
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
- [x] #1 Chegaralar: <70% oddiy provayder rangi, 70–89% ogohlantirish (sariq), ≥90% xavf (qizil); qiymatlar bitta joyda konstanta sifatida
- [x] #2 Island halqasi, ostidagi chiziq va popover progress barlari bir xil qoidani ishlatadi
- [x] #3 ≥90% holatda rangdan tashqari ham signal bor (masalan, ogohlantirish belgisi yoki yumshoq pulsatsiya), Reduce Motion yoqilgan boʻlsa animatsiya oʻchadi
- [x] #4 Regressiya: 50/80/95% uchun kutilgan ranglar
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ClaudeSessions'da UsageLevel: normal (<70), warning (70–89), critical (≥90); chegaralar bitta joyda statik konstanta. Unit testlar chegara qiymatlari bilan.
2. AppDelegate.usageColor(for:percent:): normal = provayder rangi, warning = systemYellow, critical = systemRed. Island halqasi yoyi, ostidagi CompactUsageBar va popover makeStatusBar shu funksiyadan foydalanadi; provayder logotipi oʻz rangida qoladi.
3. ≥90% holatda rangdan tashqari signal: halqa burchagida '!' belgisi va yumshoq opacity pulsatsiyasi. Reduce Motion (injectable prefersReducedMotion) yoqilgan boʻlsa animatsiya qoʻshilmaydi, belgi qoladi.
4. Usage regressiyasi: 50/80/95% uchun halqa, chiziq va popover bar ranglari, belgi va pulsatsiya (Reduce Motion yoqilgan/oʻchgan holda).
5. swift test, uchala regressiya, release build va island skrinshoti.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
UsageLevel (ClaudeSessions): warningThreshold 70, criticalThreshold 90; normal/warning/critical. AppDelegate.usageColor(accent:percent:) yagona qoida: normal = provayder rangi, warning = systemYellow, critical = systemRed. Island halqasi yoyi, CompactUsageBar va popover usageBarViews shu qoidadan foydalanadi. Provayder logotipi oʻz rangida qoladi, shuning uchun provayderni rang orqali ajratish saqlanadi.
≥90%: halqaning yuqori oʻng burchagida qizil '!' belgisi va 0.9 s opacity pulsatsiyasi (1 → 0.55). prefersReducedMotion (standart: NSWorkspace.accessibilityDisplayShouldReduceMotion) true boʻlsa pulsatsiya qoʻshilmaydi, belgi qoladi.
Tekshiruv: swift test 52/52 (UsageLevelTests 2). Usage regressiyasi 26 PASS: 50/80/95% uchun halqa, island bar va popover bar ranglari, 95% belgisi, pulsatsiya va Reduce Motion ostida pulsatsiya yoʻqligi tekshirildi. Accounts regressiyasidagi 'Codex is white and Claude is orange' tekshiruvi logotip rangini tekshiradigan qilib oʻzgartirildi, chunki halqa endi daraja rangida; Claude 96% halqasi qizil ekani tasdiqlandi. Accounts 23 PASS, settings 104 PASS. usage.<percent>.png va accounts.popover.png rasmlari koʻrib chiqildi.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Island halqasi, ostidagi chiziq va popover progress barlari endi limitga yaqinlikni rang bilan koʻrsatadi: 70% gacha provayder rangi, 70–89% sariq, 90% va undan yuqori qizil. Chegaralar UsageLevel'da bitta joyda turadi. 90% dan boshlab halqada '!' belgisi va yumshoq pulsatsiya paydo boʻladi; Reduce Motion yoqilgan boʻlsa pulsatsiya oʻchadi. Tekshirildi: swift test 52/52, regressiyalar usage 26, accounts 23, settings 104 PASS, island va popover rasmlari koʻzdan kechirildi.
<!-- SECTION:FINAL_SUMMARY:END -->
