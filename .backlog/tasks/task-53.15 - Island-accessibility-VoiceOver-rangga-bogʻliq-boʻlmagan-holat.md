---
id: TASK-53.15
title: 'Island: accessibility (VoiceOver, rangga bogʻliq boʻlmagan holat)'
status: Done
assignee:
  - '@claude'
created_date: '2026-10-10 15:13'
updated_date: '2026-10-10 19:02'
labels:
  - ai-island
  - ux
dependencies: []
references:
  - macos/AIIslandApp/Sources/AIIslandApp/main.swift
parent_task_id: TASK-53
priority: medium
type: enhancement
ordinal: 75000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`UsageRingView` va island katakchalarining accessibility label/value yoʻq — VoiceOver foizni oʻqiy olmaydi. Holatlar asosan rang bilan bildiriladi. Popover va kartalar oʻlchamlari qattiq piksellarda (356/324/296) belgilangan.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Island katakchalari VoiceOver da "Claude, 5 soatlik limit 47%, ..." kabi oʻqiladi; popover tugmalari va kartalari ham nomlangan
- [x] #2 Har bir holat (nomaʼlum, ogohlantirish, xavf, eskirgan) rangdan tashqari matn yoki belgi bilan ham bildiriladi
- [x] #3 Increase Contrast va Reduce Motion sozlamalari hurmat qilinadi
- [x] #4 Accessibility Inspector bilan qoʻlda tekshiruv natijasi task notesda
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. VoiceOver: island katakchasi bitta element boʻladi va toʻliq jumla bilan oʻqiladi (masalan "Codex, 5-hour limit 47% used, 7-day limit 20% used", holat soʻzi bilan). Ichki ring/logo/raqam/bar yashiriladi. Island oynasi "AI Island" tugmasi sifatida nomlanadi va press amali popoverni ochadi. Popover kartalari "Codex limits" kabi guruh nomini oladi, logo rasmlari nomlanadi.
2. Rangsiz holat: ogohlantirish (70%+) uchun island halqasida sariq uchburchak belgi, xavf (90%+) uchun mavjud qizil "!" doira. Popover qatorlarida "· high" va "· near limit" soʻzlari. Nomaʼlum (—, uzuq halqa) va eskirgan ("last known") holatlar saqlanadi.
3. Increase Contrast: prefersIncreasedContrast closure; xira matnlar ≥0.9 shaffoflikka, chiziqlar va treklar kuchliroq. Reduce Motion mavjud. NSWorkspace accessibilityDisplayOptionsDidChange kuzatilib island va popover qayta quriladi.
4. Regressiya: accessibility label/role, warning belgisi, matn soʻzlari, high contrast ranglari. Haqiqiy ilovani AX API orqali tekshirish natijasi notesga.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Oʻzgarishlar: island katakchasi bitta AXStaticText (masalan "Codex, 5-hour limit 100% used, near limit, 7-day limit 72% used, high"), ichki logo/raqam yashirildi (cell.setAccessibilityChildren([])). Island oynasi "AI Island" guruhi va "Show or hide limits card" custom action. Popover kartalari "Codex limits"/"Claude limits" guruhi, "●" nuqta yashirildi. Ogohlantirish uchun sariq uchburchak belgi, xavf uchun qizil "!" doira; popover qatorlarida "· high" va "· near limit". Increase Contrast: quietText/hairline yordamchilari, ring va bar highContrast; accessibilityDisplayOptionsDidChange kelganda island va ochiq popover qayta quriladi.
Qoʻlda tekshiruv: Accessibility Inspector GUI emas, aynan u oʻqiydigan AX daraxti AXUIElement API orqali release ilovada oʻqildi: AXGroup "AI Island" > AXStaticText "Codex, 5-hour limit 0% used, 7-day limit 26% used", "Claude, 5-hour limit 51% used, 7-day limit 68% used"; custom action popoverni ochdi va yopdi; AXPopover ichida AXGroup "Codex limits"/"Claude limits" va AXButton "Refresh limits", "Manage AI Island", "Update Claude Code and Codex CLI". Tizimdagi Increase Contrast sozlamasi oʻzgartirilmadi, u regressiyada tekshirildi.
Tekshiruv: swift test 54; regressiyalar settings 104, usage 51, accounts 30 PASS; foydalanuvchi config shasum oʻzgarmadi. Popover oʻlchamlari (356/324/296) oʻzgartirilmadi — AC talab qilmaydi.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
AI Island endi VoiceOver bilan oʻqiladi: har bir katakcha "Codex, 5-hour limit 47% used, ..." kabi bitta jumla, island "AI Island" guruhi va popoverni ochadigan amalga ega, popover kartalari va tugmalari nomlangan. Ogohlantirish (sariq uchburchak) va xavf (qizil "!") island halqasida belgi bilan, popoverda "high"/"near limit" soʻzlari bilan ham bildiriladi. Increase Contrast yoqilganda xira matnlar, treklar va chegaralar kuchayadi; sozlama oʻzgarsa island va popover darhol qayta quriladi. Usage regressiyasi 51 tekshiruvga yetdi.
<!-- SECTION:FINAL_SUMMARY:END -->
