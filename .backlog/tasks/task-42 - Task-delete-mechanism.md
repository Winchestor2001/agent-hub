---
id: TASK-42
title: Task delete mechanism
status: Done
assignee:
  - '@codex'
created_date: '2026-09-29 08:13'
updated_date: '2026-10-07 10:54'
labels: []
dependencies: []
ordinal: 49000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Agent Hub UI'da task yaratish, status o'zgartirish va lifecycle bor, lekin noto'g'ri yoki keraksiz tasklarni o'chirish uchun xavfsiz mexanizm yo'q. Delete destructive bo'lgani uchun foydalanuvchi tasdig'i, bog'langan jonli sessiyalarni himoya qilish va tushunarli xato holatlari kerak.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Task detail'dan taskni delete qilish uchun alohida xavfli action va confirmation bor
- [x] #2 Bog'langan jonli agent sessiyalari bo'lsa delete bloklanadi yoki foydalanuvchiga aniq sabab ko'rsatiladi
- [x] #3 Delete muvaffaqiyatli bo'lsa board/task detail/projects cache yangilanadi va task drawer yopiladi
- [x] #4 Backend delete endpoint Backlog CLI orqali metadata/history'ni buzmasdan ishlaydi
- [x] #5 Backend/frontend testlar va make check o'tadi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Backend: add BacklogClient.archive_task using backlog task archive, and DELETE /api/projects/{project_id}/tasks/{task_id}. 2. Safety: resolve task and live sessions first; if linked live sessions exist, return a clear 409 instead of archiving. 3. Frontend: add Delete danger action in TaskDetailDrawer with confirmation, error display, cache invalidation, and drawer close on success. 4. I18n/styles/tests: add uz/ru strings and API tests for success, blocked live sessions, and CLI errors. 5. Verify with focused tests, make check, and make macos-app.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented safe task delete mechanism. Backend: DELETE /api/projects/{project_id}/tasks/{task_id} resolves the task, checks linked live sessions, blocks with task_has_live_sessions when needed, and archives via backlog task archive through BacklogClient.archive_task. Frontend: Task detail has a Danger Zone with Delete action, confirmation prompt, error display, cache invalidation, and drawer close on success. Verification: API tests cover archive success and live-session blocking; i18n keys added; make check passed with 642 pytest selected passing and 124 vitest passing; make macos-app passed.

Fixed delete for terminal Done tasks: DELETE now uses backlog task complete for terminal-status tasks and backlog task archive for active tasks, matching Backlog.md cleanup rules. Verification: make check passed with 643 pytest selected and 124 vitest tests; backend restarted and DELETE route smoke-check returns project_not_found for a missing project, confirming the new route is loaded.

2026-10-07 brauzer tekshiruvi (Playwright headless Chromium, :8711 QA loyiha):
- AC#1/#2: 'Taskni o'chirish' -> tasdiqlash -> jonli sessiya bog'langan TASK-2 uchun 'Taskga 1 ta jonli sessiya bog'langan — avval sessiyalarni yoping' ko'rindi, task o'chmadi.
- Topilgan bug: useDeleteTask detail keshini olib tashlab invalidate'ni kutgani uchun DetailBody unmount bo'lib, mutate(..., {onSuccess: onClose}) ba'zan chaqirilmasdi (TASK-1 o'chdi, drawer ochiq qoldi). Tuzatish: onClose useDeleteTask(projectId, onDeleted) orqali hook darajasida chaqiriladi.
- AC#3: tuzatishdan keyin 3 ta To Do task ketma-ket o'chirildi — har safar drawer yopildi, karta doskadan yo'qoldi; To Do -> backlog/archive, Done -> backlog/completed.
- Kuzatuv: Backlog CLI arxivlangan task ID'larini yangi tasklarga qayta beradi (TASK-3/4 qayta ishlatildi) — bu CLI xatti-harakati.
- make check: 646 pytest, 124 vitest.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Task detail'da tasdiqlashli 'Taskni o'chirish' qo'shildi: bog'langan jonli sessiya bo'lsa 409 task_has_live_sessions bilan bloklanadi, aks holda Backlog CLI orqali archive (faol) yoki complete (Done) qilinadi, keshlar yangilanib drawer yopiladi. Brauzerda tekshirishda drawer yopilmaslik poygasi topildi va tuzatildi (yopish hook darajasiga ko'chirildi). Playwright bilan tekshirildi; make check o'tdi (646 pytest, 124 vitest).
<!-- SECTION:FINAL_SUMMARY:END -->
