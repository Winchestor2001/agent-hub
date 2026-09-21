---
id: TASK-34
title: Terminalga fayl/rasm paste qilish va yuklash xatolarini tushunarli qilish
status: Done
assignee:
  - '@claude'
created_date: '2026-09-21 07:55'
updated_date: '2026-09-21 08:18'
labels:
  - client
dependencies: []
ordinal: 34000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Aktiv sessiya terminalida (xterm.js) Cmd+V bilan skrinshot yoki fayl qo'yib bo'lmaydi: xterm paste paytida clipboard'dan faqat text/plain oladi, clipboardData.files e'tiborga olinmaydi, fayl yuklash faqat Vazifa yaratish/Yangi sessiya dialoglaridagi FileAttach da bor. Bundan tashqari yuklash xatolari foydalanuvchini adashtiradi: limit baytda ko'rsatiladi ("chegara: 10485760 bayt"), qo'llab-quvvatlanmaydigan tur xabarida esa qaysi turlar mumkinligi aytilmaydi (masalan video yuklamoqchi bo'lgan foydalanuvchi sababni tushunmadi). Video qo'llab-quvvatlash bu taskka kirmaydi.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Terminal ustida Cmd/Ctrl+V bilan clipboard'dagi fayl yoki rasm mavjud /api/projects/{id}/uploads orqali yuklanadi va nisbiy yo'l pane'ga matn sifatida yoziladi; faqat matn paste qilinsa xterm odatdagidek ishlaydi
- [x] #2 Yuklash jarayoni va xatosi terminal panelida ko'rinadi (yuklanayotganda indikator, xatoda ErrorText); xato bo'lsa pane'ga hech narsa yozilmaydi
- [x] #3 Yuklangan fayl qaysi loyihaga tegishli ekani pane cwd orqali aniqlanadi; loyihasi topilmagan pane uchun tushunarli xabar chiqadi
- [x] #4 error.upload_too_large xabarida limit MB da ko'rsatiladi, error.upload_type_invalid xabarida ruxsat etilgan turlar sanaladi (uz va ru)
- [x] #5 Yangi matnlar uz va ru lug'atlarida bor; backend testlari, web testlari, typecheck va lint o'tadi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Backend services/uploads.py: too_large(name) yordamchisi — upload_too_large xatosiga limit (bayt) bilan birga limit_mb ham qo'shiladi (read_upload va store bir xil joydan); check_name(raw) — kengaytmani tekshiradi. api/uploads.py: fayl tanasini o'qishdan OLDIN tur tekshiriladi, shunda katta video 'juda katta' emas, asl sabab bilan ('tur qo'llab-quvvatlanmaydi') rad etiladi.
2. i18n (uz+ru): error.upload_too_large — {limit_mb} MB; error.upload_type_invalid — ruxsat etilgan turlar ({allowed}) sanaladi; yangi terminal.upload_no_project.
3. web/src/uploads/model.ts: paneUploadDir(paneCwd, dirs) — pane papkasini o'z ichiga olgan eng ichki loyiha papkasi (segment bo'yicha, ichki papka ham mos); panePastePath(paneCwd, uploadDir, path) — papka bir xil bo'lsa nisbiy yo'l (agent ruxsatsiz o'qiydi), aks holda absolyut; bo'shliq/maxsus belgilar backslash bilan escape qilinadi. Vitest testlari.
4. web/src/terminal/usePasteUpload.ts (yangi hook): onPasteCapture — clipboard'da fayl bo'lsa preventDefault+stopPropagation (xterm paste'ni o'zi to'xtatadi va faqat text/plain oladi, shuning uchun capture fazasi), fayllarni useUploadFiles orqali pane loyihasiga (cwd=mos papka, taskId=pane.task?.id) yuklaydi va yo'llarni term.paste() bilan yozadi (bracketed paste hurmat qilinadi). Fayl yo'q bo'lsa hech narsaga tegmaydi — matn paste'i xterm'da qoladi. Pane tugagan yoki ulanish ochiq bo'lmasa aralashmaydi.
5. usePaneTerminal: pasteText(text) qo'shiladi. TerminalView: project prop, .terminal-screen ga onPasteCapture, toolbar'da 'Yuklanmoqda…' (mavjud files.uploading) va ErrorText / terminal.upload_no_project. App.tsx: pane.project_id bo'yicha loyihani uzatadi.
6. Tekshiruv: pytest, npm test/typecheck/lint, build (src/agent_hub/static); brauzerda sintetik ClipboardEvent bilan terminal yo'lini sinash.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Bajarildi: services/uploads.py — too_large() (limit bayt + limit_mb), check_name(); api/uploads.py fayl tanasini o'qishdan OLDIN turni tekshiradi (katta .mov endi 'juda katta' emas, 415 bilan rad etiladi). i18n uz+ru: upload_too_large — MB, upload_type_invalid — {allowed} ro'yxati, terminal.upload_no_project. Frontend: uploads/model.ts paneUploadDir + panePastePath (pane loyiha papkasining ichki papkasida bo'lsa absolyut yo'l, bo'shliqlar escape), terminal/usePasteUpload.ts (onPasteCapture: xterm paste'ni textarea/element'da ushlab stopPropagation qiladi va faqat text/plain oladi — shuning uchun capture fazasi; fayl yo'q bo'lsa hodisaga tegilmaydi), usePaneTerminal.pasteText (term.paste — bracketed paste hurmat qilinadi), TerminalView project prop + toolbar'da indikator/xato, App.tsx terminalPane. Yuklash papkasi: pane.task bo'lsa uploads/<task-id>/, aks holda inbox.

Tekshiruv: pytest 557 o'tdi, ruff+format+mypy toza; web: vitest 101 test (paneUploadDir/panePastePath va MB/turlar xabari uz+ru), typecheck va lint toza; npm run build src/agent_hub/static ga qilindi. xterm.js 6.0.0 ichida paste listener'lari textarea va element'ga ulangani tekshirildi. AC #1-#3 (terminaldagi haqiqiy Cmd+V) hali brauzerda sinalmagan: jonli sessiyaga yozmaslik uchun foydalanuvchi tekshiradi; backend o'zgarishlari uchun servis qayta ishga tushirilishi kerak.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Aktiv sessiya terminalida Cmd/Ctrl+V bilan clipboard'dagi fayl/rasm endi pane loyihasiga yuklanadi va yo'li pane'ga yoziladi (matn paste'i o'zgarmagan). Yuklash xatolari tushunarli: limit MB da, qo'llab-quvvatlanmaydigan turda ruxsat etilganlar ro'yxati, tur tanani o'qishdan oldin tekshiriladi. Foydalanuvchi make install dan keyin sinab tasdiqladi. Testlar: pytest, vitest, typecheck, lint, build o'tdi.
<!-- SECTION:FINAL_SUMMARY:END -->
