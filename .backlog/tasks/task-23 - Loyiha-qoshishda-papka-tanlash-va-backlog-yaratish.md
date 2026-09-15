---
id: TASK-23
title: Loyiha qo'shishda papka tanlash va backlog yaratish
status: Done
assignee:
  - '@claude'
created_date: '2026-09-15 15:46'
updated_date: '2026-09-15 16:03'
labels:
  - backend
  - client
dependencies: []
ordinal: 23000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Loyiha qo'shish dialogida bekloq va repo papkalarining to'liq yo'lini qo'lda yozish kerak; foydalanuvchi yo'llarni eslab qolmaydi va maydonlar nima uchun kerakligi tushunarsiz. ~/my-projects dagi 42 papkadan faqat 2 tasida backlog bor, shuning uchun backlog'siz papkada ham loyiha qo'shish oqimi kerak. Brauzer xavfsizlik sababli to'liq yo'lni bermaydi — tanlash backend orqali. Qarorlar (foydalanuvchi, 2026-09-15): takliflar ~/my-projects dan; backlog'siz papkada faqat tasdiqlangan tugma bilan backlog init, papka .backlog/, agent instruksiya fayllari va commit'siz.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Dialog ~/my-projects dagi hali qo'shilmagan papkalarni taklif qiladi (backlog bor/yo'q belgisi bilan); tanlansa bekloq papkasi, nomi va ID to'ladi
- [x] #2 Bekloq va repo papkalarini uy papkasi ichida papka brauzeri orqali tanlash mumkin; uy papkasidan tashqariga chiqib bo'lmaydi, fayllar ko'rsatilmaydi
- [x] #3 Backlog'siz papkada tasdiqdan keyin .backlog/ yaratiladi (CLAUDE.md/AGENTS.md va git commit'siz, git'siz papkada ham) va loyiha qo'shiladi; backlog bor papkada init rad etiladi
- [x] #4 Maydon izohlari bekloq va repo papkalari nima uchun kerakligini tushuntiradi (uz, ru)
- [x] #5 Backend va frontend testlari yangi endpoint'lar va xato holatlarini yopadi; README yangilangan
- [x] #6 Haqiqiy UI'da takliflar, brauzer va backlog yaratish tekshirilgan
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Topilmalar: backlog init --defaults --backlog-dir .backlog --integration-mode none faqat .backlog/ yaratadi, commit/instruksiya fayllarisiz; git'siz papkada --no-git bo'lmasa interaktiv savol berib exit 0 bilan hech narsa yaratmaydi -> git'siz papkaga --no-git, keyin config borligi tekshiriladi.
1. settings: home (default Path.home()) va projects_root (env AGENT_HUB_PROJECTS_ROOT > config.yaml projects_root > ~/my-projects).
2. services/folders.py: resolve_in_home (realpath, home ichida bo'lmasa path_outside_home), list_dirs (faqat papkalar, yashirinlar yo'q, tartiblangan, limit), suggestions (projects_root bevosita bolalari, registrdagi backlog_dir'lar chiqariladi, backlog borlari birinchi), in_git (yuqoriga .git qidirish).
3. backlog_client: BacklogClient.init(project_name, git) -> backlog init ... ; natijada config bo'lmasa backlog_init_failed.
4. api/folders.py: GET /api/folders?path=, GET /api/folders/suggestions, POST /api/folders/init-backlog {path, name} (backlog_exists 409). Xato kodlari uz/ru.
5. Frontend: types/queries; FolderPicker (dialog ichida ochiladigan papka brauzeri: yuqoriga, ichkariga, tanlash); AddProjectDialog: takliflar ro'yxati, bekloq papkasi + Tanlash, backlog yo'q ogohlantirishi + Backlog yaratish (tasdiq), repo papkalari ro'yxati + Papka qo'shish; izohlar yangilanadi.
6. Testlar: pytest (folders servis, API, init argv, settings) + vitest (sof yordamchilar bo'lsa). README.
7. make check, build, backend restart, Chrome'da tekshirish (init faqat scratchpad nusxasida, haqiqiy loyihalarda emas).
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Tekshiruv: make check — 471 pytest, 65 vitest, ruff/eslint/mypy/tsc toza. Haqiqiy instansiya (8700): 40 ta taklif (backlog borlari birinchi), demo tanlov nom/ID/yo'lni to'ldirdi, backlog yo'q ogohlantirishi va Qo'shish o'chiq; brauzer ~ gacha chiqadi, undan yuqoriga emas; /api/folders?path=/etc va ~/../.. -> path_outside_home; agent-hub'da init -> backlog_exists. Init faqat scratchpad nusxasida (8711, HOME almashtirilgan): demo-app'da tasdiq -> .backlog/ (CLAUDE.md yo'q), repo brauzer orqali qo'shildi, loyiha qo'shildi va doska ochildi; git-app (git repo) da init commit qilmadi (git status: ?? .backlog/). Tanlangan bekloq yo'li maydonda ~/my-projects/<nom> ko'rinishida.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Loyiha qo'shish dialogiga ~/my-projects takliflari, uy papkasi bilan cheklangan papka brauzeri (FolderPicker) va tasdiq bilan .backlog/ yaratish qo'shildi. Backend: /api/folders, /api/folders/suggestions, /api/folders/init-backlog (backlog init --defaults --integration-mode none, git'siz papkada --no-git; config yaratilmasa backlog_init_failed, bor bo'lsa backlog_exists 409), settings.projects_root. Bekloq/repo maydon izohlari uz/ru da tushuntirildi, README yangilandi. make check, pytest/vitest testlari va Chrome'da haqiqiy va scratchpad instansiyalarida tekshirildi.
<!-- SECTION:FINAL_SUMMARY:END -->
