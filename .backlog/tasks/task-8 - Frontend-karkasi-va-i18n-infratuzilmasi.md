---
id: TASK-8
title: Frontend karkasi va i18n infratuzilmasi
status: Done
assignee:
  - '@claude'
created_date: '2026-09-15 07:27'
updated_date: '2026-09-15 09:14'
labels:
  - client
milestone: m-0
dependencies:
  - TASK-1
ordinal: 8000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
3 panelli qorong'i zich layout, TanStack Query polling (2.5 s / 6 s), API client, xato bannerlari. i18n infratuzilmasi: typed lug'at, MVP'da faqat o'zbek tili.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Chap/markaz/o'ng panelli qorong'i zich layout
- [x] #2 Barcha matnlar i18n lug'atidan (uz); yangi til qo'shish uchun faqat lug'at kerak, kalit yetishmasa tsc xato beradi
- [x] #3 Polling ishlaydi; KanBot yo'q, runner yo'q, bekloq yo'q holatlari uchun aniq bannerlar
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Bog'liqliklar: @tanstack/react-query (aniq versiya); vitest (sof funksiyalar uchun unit testlar, npm test va make check ga qo'shiladi).
2. i18n (web/src/i18n): uz.ts — yassi kalitli lug'at (as const); Dictionary turi uz kalitlaridan olinadi (qiymatlar string), yangi til = Dictionary turidagi fayl + dictionaries xaritasiga bir qator. t(key, params) — {param} o'rinbosarlari turdan tekshiriladi; xato kodlari (backend {code, params, detail}) runtime tarjima qilinadi, noma'lum kod — umumiy xabar + detail. Type-test: kalit yetishmagan lug'at @ts-expect-error bilan (tsc buni kafolatlaydi). html lang tanlangan tildan.
3. API client (web/src/api): apiFetch — JSON, xato javobidan ApiError(status, code, params, detail), tarmoq xatosi network_error; backend javob turlari (health, projects, sessions).
4. Query'lar: QueryClient (retry yo'q, tab yashirin bo'lsa polling to'xtaydi); useHealth, useProjects, useLiveSessions — 2.5 s; usePastSessions — 6 s. Oxirgi ma'lumot xato paytida ham ko'rinib turadi.
5. Bannerlar: collectBanners(health, xatolar, projects) sof funksiya — backend yo'q, KanBot yo'q, runner yo'q, xavfsizlik muammolari (shell/auto-approve/versiya), backlog CLI yo'q, loyiha bekloqi topilmadi/o'qilmadi; unit testlar.
6. Layout: yuqori panel (Agent Hub, versiya, KanBot/runner indikatorlari) + bannerlar + chap (loyihalar ro'yxati, tanlash) / markaz (tanlangan loyiha, doska joyi — TASK-9) / o'ng (jonli va o'tgan sessiyalar soni — TASK-10) panellar; qorong'i zich tema, CSS o'zgaruvchilari.
7. Tekshiruv: make check (eslint, tsc, vitest), build; jonli: backend + Vite yoki static, brauzerda layout, polling (network), KanBot o'chiq/yoqiq, runner yo'q va bekloqsiz loyiha bannerlari.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- vitest 5.0.1 qo'shildi (npm test, make test/check). Rejadagi network_error o'rniga bitta backend_unreachable kodi: tarmoq xatosi, JSON bo'lmagan javob (Vite proxy) va begona format.
- i18n: yassi uz lug'ati (as const) kalitlar manbai; Dictionary = barcha MessageKey majburiy. {param} o'rinbosarlari template literal turlardan olinadi, t() parametrlari tsc'da tekshiriladi. messages.typetest.ts (@ts-expect-error) kalit yetishmasa/ortiqcha bo'lsa yoki parametr noto'g'ri bo'lsa tsc xato berishini kafolatlaydi (probe bilan tekshirildi: TS2741, TS2554). Ko'plik shakllari yo'q — TASK-17 (rus tili) da hisobga olish kerak.
- /api/sessions ikki marta so'raladi: past_limit=0 har 2.5 s (jonli), past_limit=50 har 6 s (o'tgan).
- Bannerlar collectBanners sof funksiyasida: health muammolari, /api/projects per-loyiha xatolari va query xatolaridan. Backend yo'q bo'lsa faqat bitta banner (eskirgan health muammolari ko'rsatilmaydi), takrorlar birlashtiriladi, xatolar ogohlantirishlardan oldin.
- Polling tab yashirin bo'lsa to'xtaydi (refetchIntervalInBackground: false) — ataylab.
- Jonli tekshiruvda topilgan: backend o'chganda yuqori panel 'Tekshirilmoqda…' ko'rsatardi — 'Backend javob bermayapti' qizil indikatoriga almashtirildi.
- Doska va sessiyalar panellari hozircha joy egallovchi: TASK-9 va TASK-10.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Frontend karkasi tayyor: qorong'i zich 3 panelli layout (loyihalar / doska joyi / sessiyalar), yuqori panelda KanBot, runner va agent indikatorlari, TanStack Query polling (health, projects, jonli sessiyalar 2.5 s; o'tgan sessiyalar 6 s) va xato bannerlari. API client backend {code, params, detail} xatolarini ApiError'ga, tarmoq/proxy xatolarini backend_unreachable'ga aylantiradi.

i18n: barcha matnlar typed uz lug'atidan; yangi til faqat Dictionary turidagi lug'at bilan qo'shiladi, kalit yetishmasa yoki t() parametri noto'g'ri bo'lsa tsc xato beradi (type-test fayli bilan kafolatlangan). Backend xato kodlari lug'atdan tarjima qilinadi, noma'lum kod umumiy xabarga tushadi.

Tekshiruv: make check (ruff, mypy, pytest 379, vitest 19, eslint, tsc) va make build o'tdi. Jonli brauzerda: KanBot o'chiq → KanBot banneri; KanBot yoqilgach avtomatik yangilanib runner yo'q banneri; runner ulangach bannerlar yo'qoldi va sessiyalar chiqdi; bekloqsiz loyiha uchun banner; backend to'xtatilganda bitta 'aloqa yo'q' banneri va qizil indikator, qayta yonganda UI o'zi tiklandi. Polling oraliqlari network so'rovlarida kuzatildi.

Qolgan: doska (TASK-9) va sessiyalar paneli (TASK-10); ko'plik shakllari rus tili (TASK-17) bilan.
<!-- SECTION:FINAL_SUMMARY:END -->
