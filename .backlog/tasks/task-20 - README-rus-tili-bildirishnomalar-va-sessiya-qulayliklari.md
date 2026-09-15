---
id: TASK-20
title: 'README: rus tili, bildirishnomalar va sessiya qulayliklari'
status: Done
assignee:
  - '@claude'
created_date: '2026-09-15 14:46'
updated_date: '2026-09-15 14:51'
labels:
  - docs
dependencies: []
ordinal: 20000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
README TASK-15 da yozilgan, keyin UI'ga TASK-17 (rus tili va til almashtirgich) va TASK-19 (blocked bildirishnomalari, Alt+Shift+↑/↓ navigatsiya, tugagan sessiyalarni tozalash), TASK-18 (SSE push yangilanishlar) qo'shildi. Yangi foydalanuvchi README'dan bu imkoniyatlar borligini va qanday yoqilishini bilolmaydi.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 README'da til almashtirgich va tanlov brauzerda saqlanishi tasvirlangan
- [x] #2 README'da blocked bildirishnomalari (brauzer ruxsati, tab sarlavhasidagi hisoblagich), Alt+Shift+↑/↓ va ↑/↓/Home/End, tugagan sessiyalarni tozalash tasvirlangan
- [x] #3 README'dagi buyruqlar, portlar va yo'llar hozirgi kod bilan mos (qo'lda solishtirilgan)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Kod bilan faktlarni yig'ish: til saqlash kaliti, SSE va polling intervallari (POLL_MS/PAST_POLL_MS), bildirishnoma shartlari, shortcut va fokus tugmalari, tezkor tugmalar, tugagan pane'larni olib tashlash.
2. README'da «Loyiha qo'shish» dan keyin «Foydalanish» bo'limi: til, yangilanishlar, javob kutayotgan sessiyalar va bildirishnomalar, klaviatura jadvali, tugagan sessiyalar.
3. Mavjud bo'limlardagi buyruq/port/yo'llarni Makefile, launchd shablonlari, settings.py, registry.py bilan solishtirish.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
README «Foydalanish» bo'limi qo'shildi. Faktlar kod bilan solishtirildi: LOCALE_STORAGE_KEY=agent-hub.locale, POLL_MS=2500, PAST_POLL_MS=6000, useLiveSessions refetchIntervalInBackground=true, bildirishnoma faqat granted va !document.hasFocus() da, onclick terminalni ochadi; shortcutStep Alt+Shift+↑/↓, isTextInput va dialog[open] istisnolari; focusIndex ↑/↓/Home/End; QUICK_KEYS Enter/y/n/Esc/Ctrl-C; DELETE pane — 409 pane_alive. Mavjud bo'limlar: Makefile target'lari (LOG_LINES=50, FORCE, portlar), launchd shablonlari (RunAtLoad, KeepAlive, ThrottleInterval 10), ~/Library/Logs/agent-hub, settings.py env/config.yaml/default, KANBOT_HOME, registry.py bekloq config yo'llari va Leveling default — hammasi mos, o'zgartirish kerak bo'lmadi.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
README'ga «Foydalanish» bo'limi qo'shildi: til almashtirgich va saqlanishi, SSE push va zaxira polling, javob kutayotgan sessiyalar (tab hisoblagichi, brauzer bildirishnomasi va ruxsat), klaviatura jadvali (Alt+Shift+↑/↓, ↑/↓/Home/End), tezkor tugmalar, tugagan sessiyalarni tozalash. Har bir da'vo va mavjud bo'limlardagi buyruq/port/yo'llar kod bilan qo'lda solishtirildi (Makefile, launchd shablonlari, settings.py, registry.py, web/src).
<!-- SECTION:FINAL_SUMMARY:END -->
