---
id: TASK-28
title: Bekloq papkasi har doim loyiha papkalari orasida bo'lsin
status: Done
assignee:
  - '@claude'
created_date: '2026-09-15 19:04'
updated_date: '2026-09-15 19:09'
labels:
  - backend
  - client
dependencies: []
ordinal: 28000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Hozir repos bo'sh bo'lmasa u bekloq papkasining o'rnini egallaydi: NamSoft-Education-Backend loyihasiga Admin va Frontend qo'shilgach, «Новая сессия» oynasining «Репозиторий» ro'yxatida asosiy Backend papkasi chiqmaydi va Backend'da ochilgan sessiyalar loyihaga bog'lanmaydi. Bekloq papkasi har doim birinchi loyiha papkasi bo'lsin, repos esa unga qo'shimcha.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Project.dirs = bekloq papkasi + repos (takrorsiz, bekloq papkasi birinchi); sessiyalarning loyihaga bog'lanishi, yangi sessiya papkasi tekshiruvi va standart papka shunga tayanadi
- [x] #2 repos faqat qo'shimcha papkalarni saqlaydi: registr o'qishda va yangi loyihani tekshirishda bekloq papkasi va takrorlar repos'dan olib tashlanadi; mavjud projects.yaml fayllari qo'lda o'zgartirilmasdan ishlaydi
- [x] #3 API loyiha ko'rinishida dirs maydoni; «Новая сессия» oynasi repo ro'yxatini dirs'dan oladi (bekloq papkasi birinchi va standart tanlangan)
- [x] #4 Qo'shish/tahrirlash oynasida repo papkalari maydoni «qo'shimcha» sifatida tushuntiriladi (uz/ru), README yangilanadi
- [x] #5 Testlar (registry, linking/sessions, API) yangi xatti-harakatni qamraydi
- [x] #6 Haqiqiy hub'da NamSoft-Education-Backend loyihasi uchun yangi sessiya oynasida Backend, Admin, Frontend ko'rinishi tekshirildi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. registry: Project.dirs = (backlog_dir, *repos) takrorsiz; _extra_repos(backlog_dir, repos) yordamchisi — validate_project va _from_mapping repos'dan bekloq papkasi va takrorlarni olib tashlaydi; bo'sh repos endi bekloq papkasi bilan to'ldirilmaydi.
2. views.project_view: dirs maydoni. Frontend types: dirs; NewSessionDialog dirs'dan; AddProjectDialog izohi va matnlar (qo'shimcha papkalar).
3. Testlar: registry (normallashtirish, eski fayl), linking/sessions (bekloq papkasi repos'da bo'lmasa ham), API ko'rinishi.
4. README (Loyiha qo'shish, Sozlamalar), make check/build, launchd qayta ishga tushirish, haqiqiy hub'da NamSoft yangi sessiya oynasini tekshirish.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Project.dirs = (backlog_dir, *repos) takrorsiz; repos endi faqat qo'shimcha papkalar (_extra_repos yuklashda va validate_project'da bekloq papkasi va takrorlarni olib tashlaydi), eski projects.yaml o'zgarishsiz ishlaydi. API project_view dirs qaytaradi; NewSessionDialog project.dirs ishlatadi. uz/ru matnlar va README yangilandi. Tekshiruv: make check (483 pytest, 69 vitest, lint/types toza), make build; launchd qayta ishga tushirildi; real hub 8700 da Playwright: NamSoft Репозиторий ro'yxatida Backend (tanlangan), Admin, Frontend; tahrirlash oynasida qo'shimchalar Admin, Frontend. ~/.config/agent-hub/projects.yaml o'zgartirilmadi.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Bekloq papkasi endi har doim loyiha papkalarining birinchisi: Yangi sessiya oynasida asosiy repo chiqadi va sukut bo'yicha tanlanadi, Backend sessiyalari loyihaga bog'lanadi. repos maydoni faqat qo'shimcha papkalar sifatida talqin qilinadi, eski konfiguratsiyalar ko'chirishsiz ishlaydi.
<!-- SECTION:FINAL_SUMMARY:END -->
