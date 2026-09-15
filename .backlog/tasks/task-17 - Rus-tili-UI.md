---
id: TASK-17
title: Rus tili (UI)
status: Done
assignee:
  - '@claude'
created_date: '2026-09-15 07:27'
updated_date: '2026-09-15 12:39'
labels:
  - client
milestone: m-2
dependencies:
  - TASK-12
ordinal: 17000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
i18n infratuzilmasiga rus lug'ati va til almashtirgich qo'shish.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ru lug'ati to'liq (tsc tekshiradi); almashtirgich tanlovni saqlaydi
- [x] #2 Xato kodlari ham ru/uz da tarjima qilinadi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. web/src/i18n/ru.ts: Dictionary turidagi to'liq rus lug'ati (tsc kalit yetishmasa/ortiqcha bo'lsa xato beradi). Sonlar ko'plik shaklisiz neytral yoziladi (masalan «задач: {count}»), chunki format() plural qo'llamaydi.
2. messages.ts: dictionaries = {uz, ru}; LOCALES, LOCALE_NAMES (o'z tilidagi nomi), isLocale; sof funksiyalar readLocale(storage)/writeLocale(storage, locale) — localStorage 'agent-hub.locale', try/catch, noto'g'ri qiymat → DEFAULT_LOCALE.
3. I18nProvider holatli: boshlang'ich til saqlangandan, setLocale saqlaydi; html lang yangilanadi. setLocale useI18n() qiymatiga qo'shiladi (I18n = Translator + setLocale).
4. TopBar'da til almashtirgich (select: O'zbekcha / Русский).
5. Xato kodlari: errorMessage() allaqachon error.<code> kalitiga o'giradi — ru lug'atida barcha error.* va banner.* bor; tekshiruvni test bilan mustahkamlash (ru da message() ruscha matn, noma'lum kod → error.unknown).
6. Vaqt title'i (toLocaleString) joriy til bilan.
7. Testlar: vitest (saqlash/o'qish, ru tarjimalari uz dan farqli — ruxsat etilgan istisnolardan tashqari, placeholder mosligi mavjud test), messages.typetest; make check, build, UI'da almashtirib qo'lda tekshirish.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Qarorlar: ru matnlarida ko'plik shakli yo'q («задач: {count}»), chunki format() plural qo'llamaydi. Til localStorage 'agent-hub.locale' da (readLocale/writeLocale storage xatosini yutadi, noto'g'ri qiymat → uz). setLocale I18n context orqali; html lang va Ago title (toLocaleString) joriy tilda.
Tekshiruv: make check (ruff, mypy, eslint, tsc, 452 pytest, 61 vitest); ru.ts dan error.pane_alive olib tashlanganda tsc TS2741 berdi (qaytarildi); vitest: tarjima qilinmagan kalit yo'q (SAME_IN_RU istisnolari), barcha error.*/banner.* kirillcha, errorMessage→ru («Проект «leveling» уже существует», noma'lum kod → «Непредвиденная ошибка»). Brauzer: select → Русский, html lang=ru, storage=ru, panellar ruscha; qayta yuklanganda ruscha qoldi; uz ga qaytarildi.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
UI'ga rus tili qo'shildi: to'liq ru lug'ati (Dictionary turi — kalit yetishmasa tsc xato beradi), TopBar'da O'zbekcha/Русский almashtirgichi, tanlov localStorage'da saqlanadi, html lang va sana formati tilga mos. Backend xato kodlari error.*/banner.* kalitlari orqali ikkala tilda chiqadi. Tekshirildi: make check (452 pytest, 61 vitest, tsc/eslint/mypy/ruff), tsc'da kalit olib tashlab sinov, brauzerda almashtirish va qayta yuklashda saqlanishi.
<!-- SECTION:FINAL_SUMMARY:END -->
