---
id: TASK-38.4
title: 'Claude konfiguratsiyasi: UI (ConfigView)'
status: To Do
assignee: []
created_date: '2026-09-24 16:38'
labels: []
dependencies:
  - TASK-38.2
  - TASK-38.3
parent_task_id: TASK-38
ordinal: 42000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Backend va shablonlar tayyor bo'lgach foydalanuvchi butun Claude Code tuzilmasini (rasmdagi ro'yxat) brauzerdan sozlashi kerak: default (global) darajada va ixtiyoriy ravishda har bir loyihada alohida, bitta yoki bir nechta loyihaga birdaniga.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 TopBar'dagi Konfiguratsiya tugmasi va loyiha qatoridagi belgi butun ekranli ConfigView ochadi; qamrov (Global yoki loyiha) tanlanadi va ikkalasi ixtiyoriy
- [ ] #2 Har tur uchun element ro'yxati (qidiruv bilan, 90 dan ortiq skill uchun ham qulay), muharrir, yaratish va o'chirish ishlaydi
- [ ] #3 Saqlashdan oldin o'zgarishlar diff ko'rinishida ko'rsatiladi; 409 bo'lsa foydalanuvchiga tushunarli ogohlantirish chiqadi va qayta yuklash mumkin
- [ ] #4 Shablondan yaratish, o'z fayl/matnini yuklash yoki qo'yish va qo'llanmani ko'rish ishlaydi
- [ ] #5 Qo'llash: bitta kontent global va tanlangan loyihalarga yoziladi, natija har qamrov uchun ko'rsatiladi
- [ ] #6 Global skill loyiha skilini yopishi va CLAUDE.local.md ni gitignore'ga qo'shish kerakligi haqida ogohlantirishlar ko'rinadi
- [ ] #7 uz+ru i18n to'liq, yangi npm bog'liqlik qo'shilmagan; vitest, eslint, tsc yashil
- [ ] #8 README'da konfiguratsiya bo'limi bor; make check yashil; brauzerda qo'lda tekshirilgan
<!-- AC:END -->
