---
id: TASK-4
title: backlog_client
status: Done
assignee:
  - '@claude'
created_date: '2026-09-15 07:27'
updated_date: '2026-09-15 08:11'
labels:
  - backend
milestone: m-0
dependencies:
  - TASK-3
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Backlog.md CLI'ga yagona kirish nuqtasi: subprocess (cwd, BACKLOG_CWD, stdin=DEVNULL, NO_COLOR=1, timeout), --json parsing, typed xatolar, fingerprint kesh, DoD uchun task view keshi (≤4 parallel), single-flight.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 list_tasks, view_task, statuses, labels, milestones (id→nom), task_prefix, create_task, set_status, add_label — haqiqiy chiqish fixture'lari bilan testlangan
- [x] #2 Ota-papkadagi bekloq, timeout va lock xatolari BacklogNotFound/BacklogCliError/BacklogLocked ga aylanadi (lock'da 1 marta qayta urinish)
- [x] #3 Fayllar o'zgarmasa kesh subprocess chaqirmaydi
- [x] #4 pytest -m integration vaqtinchalik papkada haqiqiy backlog bilan init/create/edit/list ni tekshiradi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Tadqiqot (Backlog.md 1.52, scratchpad'dagi probe loyiha): task list --json {schemaVersion,kind:task-list,tasks[]} (Done ham bor, drafts yo'q, DoD yo'q); task view --json {kind:task-view,task{...acceptanceCriteria[],definitionOfDone[],subtasks[],dependencies[],implementationPlan,implementationNotes,finalSummary,comments}}; config get statuses|labels|milestones — vergulli matn; task_prefix config get'da yo'q -> config.yml dan faqat o'qiladi (default task); milestone list --plain --show-completed — '  m-N: Title (x/y done)'; task create -> 'Created task TASK-N'; xatolar stderr'da exit 1: 'No Backlog.md project found', 'Task X not found', 'is being modified by another process', 'Invalid status'. CLI ~80 ms.
2. tests/fixtures/backlog/ ga haqiqiy chiqishlar (yo'llar tozalangan).
3. backlog_client.py: BacklogClient(root, executable, timeout, runner injektsiya). _run: create_subprocess_exec, cwd=root, env NO_COLOR=1 + BACKLOG_CWD=root, stdin DEVNULL, timeout -> kill. Oldindan root'da config borligi tekshiriladi (ota-papkadagi bekloq ishlatilmaydi) -> BacklogNotFound. Xatolar BacklogError(code, params): BacklogNotFound, BacklogLocked (1 marta ~0.3 s kutib qayta urinish), BacklogTaskNotFound, BacklogCliError (backlog_cli_error / backlog_timeout / backlog_cli_missing / backlog_bad_output).
4. Pydantic modellar (camelCase alias, extra ignore): TaskSummary, TaskDetail, ChecklistItem, Milestone.
5. Kesh: fingerprint = config fayli + .backlog|backlog ichidagi tasks/drafts/completed/milestones papkalari va *.md fayllarining (nom, mtime_ns, size) xeshi (faqat stat). O'qish metodlari (list_tasks, statuses, labels, milestones) fingerprint bo'yicha keshlanadi, single-flight (bir xil kalit uchun bitta subprocess). view_task keshi (id, task fayli mtime/size) bo'yicha; dod_progress(ids) ≤4 parallel. Mutatsiyadan keyin kesh tozalanadi.
6. Mutatsiyalar: create_task(title, description, status, labels, assignees, milestone, acceptance_criteria) -> id; set_status; add_label.
7. Unit testlar fake runner + fixture'lar bilan; timeout/missing binary uchun haqiqiy subprocess (soxta skript); integratsion test (pytest -m integration): tmp papkada backlog init/create/edit/list/view.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Argument injection: '-' bilan boshlanadigan sarlavha/qiymatlar opsiya bo'lib qolmasligi uchun --opt=qiymat va '--' ishlatildi (haqiqiy CLI'da tekshirildi: sarlavha '-Login sahifasi', tavsif '--draft emas').
- Bo'sh --assignee= doim beriladi, defaultAssignee qo'llanmaydi.
- Leveling'da ID 3 xonali (LEV-001 kabi) — view_task keshi fayl nomi prefiksi bo'yicha; 'lev-1' ko'rinishidagi ID'da digest'ga qaytadi. ID normalizatsiyasi TASK-6 (linking) da.
- TASK-6 uchun: task list'da 'type' maydoni bor (masalan type: bug) — bug hisoblagichida label bilan birga hisobga olish mumkin.
- Validatsiya: make check yashil (ruff, mypy --strict, 122 test, eslint, tsc); pytest -m integration — 9 passed (3 tasi yangi, haqiqiy backlog 1.52, tmp papka, prefiks lev, zero-padded 3).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
src/agent_hub/backlog_client.py qo'shildi: Backlog.md CLI'ga yagona kirish (subprocess: cwd+BACKLOG_CWD, stdin DEVNULL, NO_COLOR, timeout->kill), task list/view --json va matnli config/milestone chiqishini parsing, typed xatolar (BacklogNotFound, BacklogTaskNotFound, BacklogLocked 1 marta qayta urinish bilan, BacklogCliError: cli_error/timeout/cli_missing/bad_output), fingerprint kesh + single-flight, view keshi task fayli bo'yicha (≤4 parallel), mutatsiyalar (create_task, set_status, add_label) keshni tozalaydi. Haqiqiy CLI chiqishlari tests/fixtures/backlog/ da. Tekshiruv: tests/test_backlog_client.py (35 unit test: parsing, argv, xatolar, kesh, soxta skript bilan timeout/missing binary), tests/integration/test_backlog_live.py (haqiqiy backlog bilan init/create/edit/list/view, tashqi o'zgarishni kesh ko'rishi, xatolar); make check yashil.
<!-- SECTION:FINAL_SUMMARY:END -->
