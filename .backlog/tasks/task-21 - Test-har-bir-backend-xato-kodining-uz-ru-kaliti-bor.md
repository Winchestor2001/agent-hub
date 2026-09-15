---
id: TASK-21
title: 'Test: har bir backend xato kodining uz/ru kaliti bor'
status: To Do
assignee:
  - '@claude'
created_date: '2026-09-15 14:46'
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
- [ ] #1 Avtomatik test backend chiqaradigan barcha xato kodlarini to'playdi va har biri uchun uz.ts va ru.ts da error.<code> (yoki mos banner.*) kaliti borligini tekshiradi
- [ ] #2 Kalit olib tashlansa yoki kaliti yo'q yangi kod qo'shilsa test yiqiladi va qaysi kod ekanini ko'rsatadi (qo'lda sinab ko'rilgan)
- [ ] #3 Test make check tarkibida ishlaydi
<!-- AC:END -->
