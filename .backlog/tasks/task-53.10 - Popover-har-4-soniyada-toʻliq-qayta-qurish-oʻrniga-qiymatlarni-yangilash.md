---
id: TASK-53.10
title: 'Popover: har 4 soniyada toʻliq qayta qurish oʻrniga qiymatlarni yangilash'
status: Done
assignee:
  - '@claude'
created_date: '2026-10-10 15:13'
updated_date: '2026-10-10 18:21'
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
- [x] #1 Popover va island koʻrinishlari bir marta quriladi, yangilanishda faqat matn/progress/rang qiymatlari oʻzgaradi (tuzilma oʻzgarsa — masalan akkaunt qoʻshilsa — qayta qurish mumkin)
- [x] #2 Popover ochiq paytda tooltip va tugma hover holati yangilanishdan keyin saqlanadi
- [x] #3 Qiymat oʻzgarmasa koʻrinish umuman qayta chizilmaydi
- [x] #4 Usage regressiyasi oʻtadi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. UsageBarView: CompactUsageBar va popover makeStatusBar oʻrniga bitta oʻzgaruvchan bar (progress/accent, draw orqali). UsageRingView va bar xossalari faqat qiymat oʻzgarganda needsDisplay qiladi.
2. Island: IslandCellModel/IslandModel (Equatable) — ring, raqam, bar, tooltip, sessiya holati. layout kaliti (Claude koʻrinadimi, sessiya tafsilotlari, Continue pill) oʻzgarsa koʻrinishlar quriladi, aks holda faqat qiymatlar yoziladi; model oʻzgarmasa hech narsa qilinmaydi. rebuildNotchContent → updateNotchContent.
3. Popover: PopoverModel (kartalar va qatorlar: source, usage, note, gap). shape oʻzgarmasa mavjud label/bar qiymatlari yangilanadi (contentViewController almashtirilmaydi), oʻzgarsa qayta quriladi. rebuildUsageViews, refreshClaudeAuth va accounts onChange yagona updateUsageViews/updatePopoverContent orqali.
4. Usage regressiyasi: ochiq popoverda yangilanishdan keyin contentViewController, tugmalar va caption obyektlari bir xil (===), qiymat yangilangan, tooltip saqlangan; oʻzgarmagan yangilanishdan keyin island va popoverda needsDisplay yoʻq; island hujayralari bir xil obyekt; tuzilma oʻzgarsa (Codex oynalari yoʻqolsa) qayta quriladi.
5. swift test, uchala regressiya, release build va skrinshot.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Island: IslandModel (IslandCellModel × 2 + sessiya holati). layout kaliti (Claude koʻrinadimi, sessiya tafsilotlari, Continue pill) oʻzgarsagina buildNotchContent, aks holda apply faqat oʻzgargan hujayraga. Model teng boʻlsa updateNotchContent hech narsa qilmaydi. rebuildNotchContent → updateNotchContent.
Popover: PopoverModel (karta → source/usage/note/gap). shape bir xil boʻlsa mavjud label va barlarga faqat oʻzgargan qatorlar yoziladi, contentViewController almashtirilmaydi. shape oʻzgarsa qayta quriladi. rebuildUsageViews, refreshClaudeAuth, accounts onChange va refreshInventory endi updateUsageViews/updatePopoverContent orqali; contentViewController faqat showPopoverContent da oʻrnatiladi.
UsageBarView CompactUsageBar va makeStatusBar oʻrnini oldi (progress/accent oʻzgaruvchan, draw orqali). UsageRingView va UsageBarView xossalari, NSTextField.show va setToolTipIfChanged faqat qiymat oʻzgarganda yozadi/needsDisplay qiladi.
Eslatma: layer-backed view'larda NSView.needsDisplay false qaytaradi, kutilayotgan qayta chizish layer.needsDisplay() da koʻrinadi; regressiya ikkalasini tekshiradi va ijobiy nazorat bor (oʻzgargan halqa belgilangan).
Tekshiruv: swift test 54/54; settings 104, usage 41, accounts 30 PASS. Yangi: yangilanishdan keyin popover controller, caption, tugmalar (===) va tooltiplar saqlanadi; island hujayrasi oʻsha obyekt; oʻzgarishsiz yangilanishdan keyin popover va islandda 0 ta qayta chiziladigan view; Codex oynalari yoʻqolganda popover qayta quriladi. Foydalanuvchi fayllari shasum oʻzgarmadi. Release build: haqiqiy popover 9 soniya (2 ta yangilanish) davomida barqaror.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Island va popover endi Equatable qiymat modellaridan quriladi. Tuzilma oʻzgarmasa, yangilanish mavjud view'larga faqat oʻzgargan qiymatlarni yozadi. Popover controlleri almashtirilmaydi, shuning uchun tooltip, hover va fokus saqlanadi. Qiymat oʻzgarmasa hech narsa qayta chizilmaydi. Tuzilma oʻzgarganda (akkaunt, oyna) qayta quriladi. swift test, uchala regressiya (usage 41: in-place, qayta chizilmaslik, qayta qurish) va haqiqiy ilovada tekshirildi.
<!-- SECTION:FINAL_SUMMARY:END -->
