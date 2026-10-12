---
id: TASK-57
title: 'AI Island: orolni vaqtincha yashirish va qayta ko''rsatish'
status: Done
assignee:
  - '@claude'
created_date: '2026-10-12 09:11'
updated_date: '2026-10-12 09:14'
labels: []
dependencies: []
priority: medium
ordinal: 80000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Foydalanuvchi orolni ba'zan vaqtincha yashirib, keyin yana ko'rsatmoqchi. Status bar menyusida 'Show / hide island' bandi bor, lekin buildStatusItem() NSStatusItem'ni lokal o'zgaruvchida yaratib saqlamaydi, shuning uchun menu bar belgisi darhol yo'qoladi va bu bandga yetib bo'lmaydi. Orolning o'zida ham yashirish yo'li yo'q.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Menu bar'dagi AI Island belgisi ilova ishlab turganda doim ko'rinadi
- [x] #2 Status menyusidagi band orol holatiga qarab 'Hide Island' yoki 'Show Island' deb ataladi va orolni yashiradi/ko'rsatadi
- [x] #3 Orolni o'ng tugma bilan bosganda chiqadigan menyuda 'Hide Island' bor
- [x] #4 Orol yashirin turganda AI Island ilovasini qayta ochish (Spotlight/Finder) orolni yana ko'rsatadi
- [x] #5 Yashirish ochiq limitlar kartasini ham yopadi; swift test o'tadi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. AppDelegate'da statusItem property: belgi saqlanib qoladi.
2. toggleIsland: yashirishda statusPopover'ni yopadi; validateMenuItem band nomini Hide/Show Island qilib yangilaydi.
3. compactContent.menu: o'ng tugma menyusi (Hide Island, Open Settings…, Quit AI Island).
4. applicationShouldHandleReopen: yashirin orolni ko'rsatadi.
5. Uzbek tarjimalar, swift test, dist build va qo'lda tekshiruv.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Amalga oshirildi: statusItem property (belgi endi yo'qolmaydi), toggleIsland yashirishda limit kartasini yopadi, validateMenuItem band nomini Hide/Show Island qiladi, compactContent.menu o'ng tugma menyusi (Hide Island, Open Settings…, Quit), applicationShouldHandleReopen yashirin orolni ko'rsatadi. Yashirin holat saqlanmaydi (vaqtinchalik). swift test 66/66 o'tdi. dist ilovasida System Events orqali: menu bar 2 da ' AI' belgisi bor; status menyusi 'Hide Island' -> oynalar 1->0, band 'Show Island' ga o'zgardi; open "dist/AI Island.app" -> 0->1; o'ng tugma (AXShowMenu) menyusida Hide Island, Open Settings…, Quit AI Island; Hide Island -> 1->0.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Orolni vaqtincha yashirish mumkin: menu bar'dagi ' AI' belgisi (endi saqlanadi, avval darhol yo'qolardi) va orolning o'ng tugma menyusida 'Hide Island'; qayta ko'rsatish — menu bar'dagi 'Show Island' yoki ilovani qayta ochish. Tekshiruv: swift test 66/66, dist ilovasida System Events skripti bilan hide/show/reopen va context menu oqimlari.
<!-- SECTION:FINAL_SUMMARY:END -->
