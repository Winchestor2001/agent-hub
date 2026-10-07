---
id: TASK-41
title: Task lifecycle automation
status: Done
assignee:
  - '@claude'
created_date: '2026-09-29 06:50'
updated_date: '2026-10-07 10:54'
labels: []
dependencies: []
ordinal: 48000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Foydalanuvchi hozir taskni o'zi yaratadi, sessiyani o'zi ochadi va Kanban'da In Progress/Done'ga o'zi ko'chiradi. Agent Hub task yaratilgandan keyin kerak bo'lsa agent session'ni o'zi ochishi, taskni In Progress'ga olib o'tishi va ish tekshirilgach Done qilish uchun xavfsiz, kuzatiladigan workflow berishi kerak.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Task yaratish yoki task detail'dan agent session'ni avtomatik start qilish mumkin
- [x] #2 Session start bo'lganda bog'langan task In Progress statusiga xavfsiz o'tadi
- [x] #3 Agent ishni tugatgach verification/acceptance holati ko'rinadi va Done'ga o'tkazish nazoratli bajariladi
- [x] #4 Avtomatik lifecycle xatolari UI'da tushunarli ko'rinadi va task qo'lda boshqarishga qaytishi mumkin
- [x] #5 Backend/frontend testlar va make check o'tadi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Audit current task create/detail, board, and session start flows to reuse existing APIs and avoid duplicating Backlog writes. 2. Add backend lifecycle helpers/endpoints that can safely move a linked task to In Progress before starting an agent session, and move it to Done only through an explicit reviewed action. 3. Extend frontend task create/detail UI with smart start controls: choose agent, start session, show lifecycle status/errors, and keep manual Kanban control available. 4. Surface verification/done readiness from existing task AC progress, live/finished sessions, and explicit user action rather than silently marking work Done. 5. Add backend/frontend tests and run make check.

6. (2026-10-07, AC #4) Sessiya ochish lifecycle'ni bloklamasin: loyihada In Progress statusi bo'lmasa yoki set_status xato bersa pane baribir qaytadi, javobda lifecycle {promoted, status, error}; NewSessionDialog xatoni ko'rsatib, qayta Start'ni o'chiradi va statusni qo'lda o'zgartirishni tavsiya qiladi. _named_status takrorlanishi bitta yordamchiga birlashtiriladi.

7. Brauzerda (Agent Hub UI) create -> session -> AC belgilash -> Done oqimini qo'lda tekshirish.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented lifecycle automation slice. Backend: linked session start promotes a task to In Progress after KanBot session start succeeds, and does not promote if KanBot start fails; explicit POST /api/projects/{project_id}/tasks/{task_id}/complete moves reviewed tasks to Done. Frontend: Create Task can open a linked session after creation; New Session explains that linked tasks move to In Progress; Task detail shows lifecycle review state and a guarded Checked -> Done action that is disabled until all ACs are complete. Verification: focused API tests passed for start promotion, no promotion on KanBot down, in-progress no rewrite, and complete endpoint; web typecheck/lint/i18n focused tests passed; make check passed with 638 pytest selected passing and 124 vitest passing; make macos-app passed.

Continued lifecycle slice: added acceptance checklist check/uncheck support through POST /api/projects/{project_id}/tasks/{task_id}/acceptance/{index}, backed by backlog task edit --check-ac/--uncheck-ac. Task detail now renders acceptance criteria as interactive checkboxes, so the user can review agent output, tick ACs in the UI, and then use the guarded Checked -> Done action. Verification: added API tests for set_acceptance and rejection cases; make check passed with 640 pytest selected passing and 124 vitest passing; make macos-app passed.

2026-10-07 brauzer tekshiruvi (Chrome kengaytmasi ulanmagani uchun Playwright headless Chromium, vaqtinchalik backend :8711, QA loyiha):
- AC#1: '+ Vazifa' -> 'Yaratgandan keyin agent sessiyasini ochish' -> NewSessionDialog yangi task tanlangan holda ochildi -> 'Ochish' -> status To Do -> In Progress, drawer'da lifecycle kartasi.
- AC#3: AC 0/2 va 1/2 da 'Tekshirildi -> Done' disabled; ikkala checkbox UI'dan belgilangach enabled; bosilganda status Done.
- AC#4: loyihada 'In Progress' statusi bo'lmaganda sessiya ochildi, dialog 'Ochish' o'rniga ogohlantirish va lifecycle_status_missing xatosini ko'rsatdi (qayta Start yo'q); keyin status drawer'dan qo'lda Doing'ga o'zgartirildi.
- Backend: sessiya ochilgandan keyin lifecycle xatosi javobni yiqitmaydi (lifecycle.error), test_start_session_when_project_has_no_in_progress_status va test_start_session_keeps_pane_when_status_update_fails qo'shildi.
- make check: ruff/mypy/eslint/tsc o'tdi, 646 pytest, 124 vitest.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Task lifecycle avtomatlashtirildi: task yaratilgandan yoki detail'dan sessiya ochish, sessiya start bo'lganda bog'langan task In Progress'ga o'tadi, AC'lar drawer'da belgilanadi va Done faqat barcha AC bajarilgach qo'lda 'Tekshirildi -> Done' bilan qilinadi. Status o'zgarmasa sessiya baribir ochiladi, xato dialogda ko'rinadi va qayta Start bloklanadi. Playwright orqali brauzerda butun oqim (create -> session -> In Progress -> AC -> Done, xato holati, qo'lda status) tekshirildi; make check o'tdi (646 pytest, 124 vitest).
<!-- SECTION:FINAL_SUMMARY:END -->
