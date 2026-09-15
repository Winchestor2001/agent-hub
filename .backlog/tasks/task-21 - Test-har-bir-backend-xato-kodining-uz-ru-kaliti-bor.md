---
id: TASK-21
title: 'Test: har bir backend xato kodining uz/ru kaliti bor'
status: Done
assignee:
  - '@claude'
created_date: '2026-09-15 14:46'
updated_date: '2026-09-15 14:57'
labels:
  - backend
  - client
dependencies: []
ordinal: 21000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
UI backend xato kodini error.<code> kalitiga o'giradi; kalit yo'q bo'lsa foydalanuvchi faqat «Kutilmagan xato (code)» ko'radi. Hozir backend kodlari (ApiError, *Error.code atributlari, registry/sessiya/xavfsizlik xatolari) va uz.ts/ru.ts kalitlari mosligi faqat qo'lda grep bilan tekshirilgan (TASK-17). Yangi kod qo'shilganda tarjima unutilsa, hech bir test yiqilmaydi.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Avtomatik test backend chiqaradigan barcha xato kodlarini to'playdi va har biri uchun uz.ts va ru.ts da error.<code> (yoki mos banner.*) kaliti borligini tekshiradi
- [x] #2 Kalit olib tashlansa yoki kaliti yo'q yangi kod qo'shilsa test yiqiladi va qaysi kod ekanini ko'rsatadi (qo'lda sinab ko'rilgan)
- [x] #3 Test make check tarkibida ishlaydi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. tests/test_i18n_keys.py (pytest, make check ichida): src/agent_hub/**/*.py ni AST bilan skanerlash — ApiError(status, "code"), RegistryError/SessionError/Problem("code"), error_response/error_body, code= kalit so'zli argument va parametr default'i, klass atributi code = "..." (IfExp ichidagilar ham), _describe va HostOriginGuard.rejection qaytaradigan tuple kodlari; terminal _error("x") → terminal.error_x.
2. web/src/i18n/uz.ts va ru.ts kalitlarini o'qish; qoida: error.<code> majburiy, health Problem kodlari uchun banner.<code> ham qabul qilinadi. Yetishmasa — kod, fayl:qator va til bilan xabar.
3. Skaner buzilib hech narsa topmay qolmasligi uchun ma'lum kodlar namunasi to'planganini tekshirish.
4. Topilgan bo'shliqlarni to'ldirish (forbidden_host, forbidden_origin — uz/ru).
5. Qo'lda sinov: kalitni olib tashlash va kaliti yo'q kod qo'shish → test yiqilishi; make check.
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
tests/test_i18n_keys.py qo'shildi: src/agent_hub ni AST bilan skanerlab 48 ta xato kodini yig'adi (ApiError, RegistryError/SessionError/Problem, error_response/error_body, code= argument va default, klass atributi code, _describe va HostOriginGuard.rejection tuple'lari, terminal _error → terminal.error_*). Har kod uchun uz.ts va ru.ts da error.<code> talab qilinadi (Problem uchun banner.<code> ham bo'ladi). IfExp shartidagi satrlar (agent == "shell") kod hisoblanmaydi. frontend_not_built istisno: index.html yo'qligida UI yuklanmaydi. Skaner buzilmaganini ma'lum kodlar namunasi tekshiradi.

Test topgan bo'shliq to'ldirildi: error.forbidden_host va error.forbidden_origin (uz/ru).

Tekshiruv: ru.ts dan error.pane_alive olib tashlandi → test yiqildi va 'pane_alive — api/sessions.py:160' ko'rsatdi; views.py ga ApiError(400, "brand_new_code") qo'shildi → uz va ru ikkalasida yiqildi; ikkala o'zgarish qaytarildi. make check: 456 backend + 61 frontend test o'tdi, ruff/mypy/eslint/tsc toza.
<!-- SECTION:FINAL_SUMMARY:END -->
