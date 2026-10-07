---
id: TASK-36
title: Video yuklash va fayl hajmi limitini olib tashlash
status: Done
assignee:
  - '@claude'
created_date: '2026-09-21 08:20'
updated_date: '2026-09-24 16:10'
labels:
  - client
dependencies: []
ordinal: 36000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Foydalanuvchi vazifa yaratishda video yuklamoqchi edi, lekin video turlari (.mp4, .mov, ...) ruxsat etilmagan va bitta fayl 10 MB bilan cheklangan (TASK-34 da faqat xabarlar tushunarli qilindi). Video qo'llab-quvvatlansin va hajm limiti olib tashlansin. Limit yo'q bo'lgani uchun fayl tanasi xotirada to'planmasligi kerak (hozir read_upload butun faylni bytes ro'yxatiga yig'adi): diskka bo'lak-bo'lak yozilsin va og'ir yozish event loop'ni to'xtatmasin. Bir martada 10 tagacha fayl cheklovi saqlanadi.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Video fayllar (.mp4, .mov, .webm, .m4v, .mkv, .avi) yuklanadi va kind="video" bo'ladi; UI da alohida belgi bilan ko'rinadi
- [x] #2 Bitta fayl hajmiga limit yo'q: 10 MB dan katta fayl ham to'liq saqlanadi; upload_too_large xatosi va uning matnlari (uz/ru) olib tashlanadi
- [x] #3 Fayl tanasi xotirada to'planmaydi: diskka bo'lak-bo'lak yoziladi (threadpool'da); xato yoki bo'sh fayl bo'lsa yarim yozilgan fayl o'chiriladi
- [x] #4 README va testlar yangilanadi (video turi, limit yo'qligi, shortcut tartibi va terminal paste tavsifi); pytest, vitest, typecheck, lint va build o'tadi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. services/uploads.py: VIDEO_EXTENSIONS ALLOWED ga, StoredFile.kind video, MAX_FILE_BYTES/too_large/read_upload olib tashlanadi, iter_file(file) qo'shiladi. 2. api/uploads.py: store ni run_in_threadpool orqali upload.file dan bo'laklab yozadi; api/errors.py va i18n dan upload_too_large olib tashlanadi. 3. Frontend: UploadedFile.kind ga video, FileAttach da 🎬; files.hint matniga video qo'shiladi. 4. Testlar yangilanadi (video qabul, 10 MB+ fayl, kind, xato tozalash). 5. README: turlar, limit yo'qligi, terminal paste, shortcut tartibi. 6. pytest/ruff/mypy, vitest/tsc/eslint/build.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
services/uploads.py: VIDEO_EXTENSIONS (.mp4 .mov .webm .m4v .mkv .avi) ruxsat etilgan turlarga, StoredFile.kind video; MAX_FILE_BYTES, too_large, read_upload olib tashlandi, iter_file(file) qo'shildi. api/uploads.py: store run_in_threadpool orqali upload.file dan bo'lak-bo'lak yozadi (Starlette multipart'ni allaqachon diskka spool qiladi, xotirada to'planmaydi); xatoda yarim fayl o'chiriladi (store'dagi mavjud except). api/errors.py va uz/ru i18n dan upload_too_large olib tashlandi. Frontend: UploadedFile.kind ga video, FileAttach da 🎬, files.hint da 'video'. README yangilandi (turlar, limit yo'qligi, terminal paste, sessiyalar tartibi va shortcut). Testlar: 11 MB fayl saqlanadi, video qabul (kind=video), yarim fayl o'chadi, iter_file; pytest 566, vitest 99, ruff/mypy/tsc/eslint/build toza. Haqiqiy katta video brauzerdan sinalmagan — make install dan keyin foydalanuvchi tekshiradi.
<!-- SECTION:NOTES:END -->
