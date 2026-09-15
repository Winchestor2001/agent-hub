---
id: TASK-27
title: Loyihani tahrirlash
status: Done
assignee:
  - '@claude'
created_date: '2026-09-15 18:48'
updated_date: '2026-09-15 18:57'
labels:
  - backend
  - client
dependencies: []
ordinal: 27000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Hozir loyiha registrida faqat qo'shish va o'chirish bor: nomi, backlog papkasi yoki repo papkalarini o'zgartirish uchun loyihani o'chirib, qaytadan qo'shish kerak. Loyihalar panelida har bir loyihani tahrirlash imkoniyati kerak.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 PUT /api/projects/{id} loyiha nomi, backlog papkasi va repo papkalarini yangilaydi; ID o'zgarmaydi; qo'shishdagi tekshiruvlar (papka mavjud, backlog topildi) qo'llanadi; yo'q loyiha uchun project_not_found
- [x] #2 Backlog papkasi o'zgarsa eski papka keshi (boshqa loyiha ishlatmasa) tashlab yuboriladi va doska, hisoblagichlar yangi papkadan o'qiladi
- [x] #3 Loyihalar panelida har bir loyiha yonida tahrirlash tugmasi; dialog joriy qiymatlar bilan ochiladi (ID faqat o'qish uchun), papka tanlash va backlog yaratish qo'shish dialogidagidek ishlaydi
- [x] #4 Saqlangach ro'yxat, doska va sessiyalarning loyihaga bog'lanishi yangilanadi; xato dialog ichida ko'rsatiladi
- [x] #5 Backend (registry, API) testlari, uz/ru matnlar, README
- [x] #6 Haqiqiy UI'da test instansiyada tekshirildi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Registry.update(project): mavjud ID'ni joyida almashtiradi (tartib saqlanadi), topilmasa project_not_found.
2. API: ProjectUpdate (name, backlog_dir, repos) va PUT /api/projects/{id} — validate_project bilan tekshiruv; backlog_dir o'zgarsa va eski papkani boshqa loyiha ishlatmasa hub.forget_backlog(eski).
3. Frontend: useUpdateProject (projects, board, tasks, sessions invalidatsiya); AddProjectDialog'ni 'edit' rejimiga moslash (boshlang'ich qiymatlar, ID o'qish uchun, nom papkadan avtomatik olinmaydi, sarlavha/tugma matni); ProjectsPanel qatorida ✎ tugmasi.
4. Testlar: test_registry, tests/api loyiha testlari; uz/ru kalitlar; README.
5. make check, make build, Playwright bilan test instansiyada tekshiruv.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Qilindi: Registry.update (ID bo'yicha joyida almashtiradi, tartib saqlanadi); PUT /api/projects/{id} (ProjectUpdate: name, backlog_dir, repos; extra=forbid, ID body'da qabul qilinmaydi) validate_project bilan; eski bekloq papkasini boshqa loyiha ishlatmasa klient keshi tashlanadi (_forget_unused_backlog, DELETE bilan umumiy). Frontend: apiFetch PUT, useUpdateProject (projects, board, tasks, sessions, folders invalidatsiya); AddProjectDialog 'project' prop bilan tahrirlash rejimi — tavsiyalar ro'yxati yashirin, ID readOnly, nom papkadan avtomatik olinmaydi, repo papkalari saqlangan holida (bekloq papkasi ham) ko'rsatiladi, shunda yangi papka qo'shilganda u jimgina tushib qolmaydi; ProjectsPanel qatorida hover'da × ostida ✎. uz/ru (projects.edit, edit_title, field_id_readonly, common.save), CSS, README.
Tekshiruv: make check — 480 pytest (+3: registry update, API update, update validation), 69 vitest, ruff/eslint/mypy/tsc toza; make build.
UI (Playwright headless Chromium, 8711 test instansiya, soxta KanBot): ✎ hover'da ko'rinadi; dialog 'Loyihani tahrirlash', nom/ID/bekloq/repo oldindan to'ldirilgan, ID readonly, tavsiyalar yo'q, 'Saqlash'; bekloqsiz papkada ogohlantirish va Saqlash o'chiq; nom o'zgartirildi va papka brauzeri orqali ~/elsewhere repo qo'shildi — ro'yxatda yangi nom, projects.yaml yangilandi, loyihadan tashqaridagi sessiya endi shu loyihaning Jonli agentlar bo'limida; mavjud bo'lmagan repo bilan saqlash — xato dialog ichida, registr o'zgarmadi; ru matnlar; konsolda faqat kutilgan 422. Haqiqiy hub (launchd) PUT yo'li uchun qayta ishga tushirildi.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Loyihalar panelida har bir loyihani tahrirlash (✎) qo'shildi: nom, bekloq papkasi va repo papkalari o'zgartiriladi, ID o'zgarmaydi. Backend: Registry.update va PUT /api/projects/{id} (qo'shishdagi tekshiruvlar, eskirgan bekloq keshi tashlanadi). Frontend: qo'shish dialogi tahrirlash rejimiga moslandi, saqlangach ro'yxat, doska va sessiyalarning loyihaga bog'lanishi yangilanadi, xato dialog ichida. uz/ru, README. Tekshiruv: make check (480 pytest, 69 vitest) va Playwright UI skripti test instansiyada.
<!-- SECTION:FINAL_SUMMARY:END -->
