---
id: TASK-52
title: >-
  AI Island popover: Update tugmasi (Claude va Codex CLI yangilash) va ikonli
  tugmalar
status: Done
assignee:
  - '@claude'
created_date: '2026-10-08 12:41'
updated_date: '2026-10-08 12:44'
labels:
  - ai-island
dependencies: []
ordinal: 59000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Foydalanuvchi popover'dagi 'Accounts →' tugmasi o'rniga CLI'larni yangilaydigan Update tugmasini xohlaydi; Refresh/Settings/Update matn emas, ikon bo'lsin. Ikkala CLI Homebrew cask (claude-code@latest, codex) orqali o'rnatilgan; 'claude update' va 'codex update' o'z o'rnatish usulini aniqlaydi. Akkauntlar oynasi o'ng tugma menyusi va sozlamalar sahifasi orqali ochilaveradi.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Popover pastida uchta ikon tugma: Refresh (arrow.clockwise), Settings (gearshape), Update (arrow.down.circle); har birida tooltip va accessibility nomi; 'Accounts →' tugmasi olib tashlangan
- [x] #2 Update tugmasi Terminal'da 'claude update' va 'codex update' ni ketma-ket ishga tushiradi (topilmagan CLI o'tkazib yuboriladi), natija Terminal'da ko'rinadi
- [x] #3 Native regressiyada popover tugmalari (ikon, tooltip, Accounts yo'qligi) va update skripti mazmuni tekshiriladi (Terminal ochilmaydi); swift test, release build, app qayta ochiladi
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Tekshiruv: accounts regression 22/22 (ikon tugmalar: tooltip/accessibility, sarlavhasiz, Accounts yo'q; Update tugmasi bosilganda .command skript ochiladi — stub orqali, Terminal ochilmadi), usage regression 14/14, swift test 28/28, skript 'sh -n' bilan tekshirildi, popover snapshot ko'rildi. Akkauntlar oynasi o'ng tugma menyusi va sozlamalar sahifasidan ochiladi.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Popover pastidagi tugmalar ikon bo'ldi: Refresh, Settings, Update; Accounts tugmasi olib tashlandi. Update Terminal'da 'claude update' va 'codex update' ni ketma-ket ishga tushiradi (versiyalarni oldin/keyin ko'rsatadi, topilmagan CLI o'tkaziladi). Tekshiruv: regressiyalar 22/22 va 14/14, swift test 28/28, release build.
<!-- SECTION:FINAL_SUMMARY:END -->
