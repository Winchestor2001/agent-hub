---
id: TASK-53.4
title: 'Popover: "Hover to peek" va hover xatti-harakatini moslash'
status: Done
assignee:
  - '@claude'
created_date: '2026-10-10 15:13'
updated_date: '2026-10-10 16:08'
labels:
  - ai-island
  - ux
dependencies: []
references:
  - macos/AIIslandApp/Sources/AIIslandApp/main.swift
parent_task_id: TASK-53
priority: high
type: bug
ordinal: 64000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Popover subtitle "Hover to peek · click to keep open" deydi, lekin `NotchContentView.onPointerEnter/onPointerExit` hech qayerda ulanmagan va `schedulePopoverClose` chaqirilmaydi — popover faqat bosish bilan ochiladi. `popoverPinned` mantigʻi ham shu sababli amalda ishlamaydi. Interfeys va xatti-harakat bir-biriga mos boʻlishi kerak.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Yoki hover haqiqatan ishlaydi (kursor island ustiga kelganda kichik kechikish bilan ochiladi, chiqib ketganda ~0.6s dan keyin yopiladi, bosish pin qiladi), yoki matn va oʻlik kod (pinned/hover) olib tashlanadi — tanlov task notesda asoslanadi
- [x] #2 Subtitle matni haqiqiy xatti-harakatni tasvirlaydi
- [x] #3 Island sudrab koʻchirilganda popover tasodifan ochilmaydi
- [x] #4 Usage regressiyasi tanlangan xatti-harakatni tekshiradi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Foydalanuvchi tanlovi: popover faqat bosish bilan ochiladi/yopiladi. Hover/pinned oʻlik kodi olib tashlanadi: NotchContentView (onPointerEnter/Exit, tracking area), popoverPinned, closeWorkItem, schedulePopoverClose.
2. toggleExpanded: popover ochiq boʻlsa yopadi, yopiq boʻlsa ochadi.
3. Subtitle haqiqiy xatti-harakatni tasvirlaydi (island yoki tashqariga bosilsa yopiladi); matn inglizcha, tarjima TASK-53.16.
4. Sudrash himoyasi: local mouse monitor island ustidagi leftMouseDown paytida oyna originini saqlaydi; toggleExpanded island shu bosishdan keyin koʻchgan boʻlsa (>2pt) popover ochmaydi.
5. Usage regressiyasi: island bosilishi popover'ni ochadi va qayta bosish yopadi; subtitle'da Hover yoʻq; mouseDown'dan keyin koʻchirilgan island popover ochmaydi.
6. swift test, usage + accounts regressiyalari, release build va qoʻlda tekshiruv.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Tanlov (foydalanuvchi bilan kelishildi): popover faqat bosish bilan ochiladi. Sabablar: kursor island ustiga kelganda TASK-53.5 dagi limit tooltipi allaqachon tez koʻrinish beradi; island yonidan oʻtganda hover popover tasodifan ochilib ekranni toʻsar edi; pinned/hover holatlari mantiqni murakkablashtirardi. Olib tashlangan kod: NotchContentView (onPointerEnter/Exit, tracking area), popoverPinned, closeWorkItem va schedulePopoverClose. Sudrashdan himoya: local leftMouseDown monitori island originini saqlaydi; toggleExpanded oyna 2pt dan koʻp siljigan boʻlsa popover ochmaydi. Tekshiruv: usage regressiyasi 22/22 PASS (3 ta yangi: bosish ochadi va subtitle toʻgʻri, ikkinchi bosish yopadi, mouseDown dan keyin koʻchirilgan island popover ochmaydi), accounts 22 PASS, settings 101 PASS, swift test 0 xato, release build qayta ochildi. Haqiqiy sichqoncha bilan sudrash agent tomonidan qilinmadi (accessibility ruxsati yoʻq) — regressiya haqiqiy NSEvent orqali monitor handleriga va oyna siljishiga tayanadi.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Popover endi faqat bosish bilan ishlaydi: island bosilsa ochiladi, island yoki tashqariga bosilsa yopiladi. Subtitle shuni aytadi ("Click the island or outside to close"). Ishlatilmayotgan hover/pinned kodi olib tashlandi. Island sudrab koʻchirilganda popover ochilmasligi uchun mouseDown paytidagi origin bilan solishtirish qoʻshildi. Tekshiruv: usage regressiyasi (22/22, 3 ta yangi check), accounts va settings regressiyalari, swift test, release build.
<!-- SECTION:FINAL_SUMMARY:END -->
