---
id: TASK-15
title: README
status: Done
assignee:
  - '@claude'
created_date: '2026-09-15 07:27'
updated_date: '2026-09-15 11:14'
labels: []
milestone: m-1
dependencies:
  - TASK-14
ordinal: 15000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Foydalanuvchi hujjati.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Nima ekani, o'rnatish, dev-rejim (KanBot va Agent Hub'ni qo'lda ishga tushirish), loyiha qo'shish
- [x] #2 Servislarni o'chirish, loglar joyi, xavfsizlik eslatmalari, KanBot yangilangandan keyin runner'ni qayta ishga tushirish
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
README.md ni to'liq qilish (faqat hujjat, kod o'zgarmaydi):
1. Qoralama eslatmasini olib tashlash; nima ekani va arxitektura sxemasi (brauzer -> Agent Hub 8700 -> KanBot 8787 -> runner -> claude/codex; backlog CLI).
2. O'rnatish: talablar, make sync, KanBot xavfsiz sozlash, make install, make status; servislar jadvali (label, buyruq, port, log).
3. Mavjud dev-rejim bo'limini saqlash, launchd servislari bilan birga ishlatmaslik ogohlantirishi.
4. Loyiha qo'shish: UI '+ Loyiha' va projects.yaml.
5. Yangilash: Agent Hub (git pull, make sync, make install, backend kickstart) va KanBot (uv tool upgrade, server+runner kickstart, pane'lar to'xtaydi).
6. O'chirish (make uninstall, FORCE), loglar joyi (make logs), xavfsizlik eslatmalari, muammolar.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
README qayta yozildi: arxitektura sxemasi, talablar, launchd o'rnatish (make install/status, FORCE, servislar jadvali), loyiha qo'shish (UI va projects.yaml), yangilash (Agent Hub va KanBot, kickstart), o'chirish, loglar, xavfsizlik, dev-rejim ogohlantirishi. Da'volar kod bilan tekshirildi (registry, --safe, i18n).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
README'ga o'rnatish, servislarni boshqarish, yangilash/KanBot'dan keyin runner'ni qayta ishga tushirish, o'chirish, loglar va xavfsizlik bo'limlari qo'shildi; dev-rejim va sozlamalar bo'limlari saqlandi. make check yashil.
<!-- SECTION:FINAL_SUMMARY:END -->
