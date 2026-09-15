---
id: TASK-7
title: REST API
status: Done
assignee:
  - '@claude'
created_date: '2026-09-15 07:27'
updated_date: '2026-09-15 08:56'
labels:
  - backend
milestone: m-0
dependencies:
  - TASK-6
ordinal: 7000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
api/ routerlari: health, projects CRUD+summary, board, task detail, task create/status/label, sessions (jonli+o'tgan), new session, resume, kill. Xato formati {code, params, detail}.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Board, detail va mutatsiyalar mock clientlar bilan testlangan
- [x] #2 KanBot o'chiq bo'lsa /sessions 503 kanbot_unavailable, /board esa 200
- [x] #3 Resume sessiyaning asl cwd'ida; loyihadan tashqaridagi cwd rad etiladi; runner'da yo'q agent rad etiladi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. api/ paketi: errors.py (ApiError va BacklogError/KanbotError/RegistryError/SessionError/RequestValidationError -> {code, params, detail} + HTTP status xaritasi), deps.py (Hub: registry, KanbotClient, loyiha bo'yicha keshlangan BacklogClient fabrikasi, StateResolver, SessionService).
2. health.py: mavjud /api/health app.py dan ko'chiriladi.
3. projects.py: GET /api/projects (har loyiha + summary; bekloq xatosi loyiha ichida error, KanBot o'chiq bo'lsa sessiya hisoblagichlari null), POST /api/projects, DELETE /api/projects/{id}, GET /api/projects/{id}/summary.
4. board.py: GET /api/projects/{id}/board (statuses, labels, milestones, task_prefix, kartochkalar: AC/DoD progress, bog'langan jonli sessiyalar; KanBot o'chiq bo'lsa ham 200, kanbot_available=false). GET .../tasks/{task_id} (detal + sessiyalar). POST .../tasks (yaratish), POST .../tasks/{id}/status (config statuslari bilan tekshiriladi), POST .../tasks/{id}/labels. Task ID prefiks regex bilan tekshiriladi.
5. sessions.py: GET /api/sessions?project= (live: tirik pane'lar effective_state, loyiha va vazifa bog'lanishi bilan, blocked tepada; past: registrdagi loyihalarga tegishli agent-sessions, mtime bo'yicha). KanBot o'chiq -> 503 kanbot_unavailable. POST /api/projects/{id}/sessions (agent, cwd, task_id, prompt). POST /api/projects/{id}/sessions/resume {agent, session_id} — sessiya KanBot ro'yxatidan olinadi (cwd klientdan qabul qilinmaydi), faol sessiya 409. POST /api/sessions/{pane_id}/kill.
6. Testlar: respx (KanBot) + FakeRunner'li BacklogClient (bekloq) bilan board, detail, mutatsiyalar, 503/200, resume cwd/agent rad etish, xato formati.
7. make check.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Qarorlar:
- board/detail/mutatsiyalar rejadagi board.py o'rniga api/tasks.py da (prefix /api/projects/{id}).
- Xato formati {code, params, detail}: RegistryError 404/409/422, SessionError 409 (runner_offline, agent_unavailable, runner_unsafe) yoki 422, BacklogError 503/404/409/504/502, KanbotError 503/409/404/502, validatsiya 422 validation_error (params.errors), qolgan hammasi 500 internal_error.
- JSON snake_case; board DoD progressi task view keshidan olinadi; KanBot o'chiq bo'lsa board/projects 200 va kanbot_available=false, sessiya hisoblagichlari null.
- Resume: cwd klientdan qabul qilinmaydi (extra=forbid), KanBot agent-sessions ro'yxatidan olinadi; faol sessiya 409 session_active, topilmasa 404 session_not_found.
- O'tgan sessiyalar faqat registrdagi loyiha papkalari ichidagilar, mtime bo'yicha, past_limit (0..500).
Tekshiruv: make check yashil (ruff, mypy strict, 379 test). Jonli: port 8711, vaqtinchalik demo bekloq — loyiha qo'shish 201, vazifa yaratish/status/label, noto'g'ri status 422, KanBot o'chiq: /board 200, /sessions 503 kanbot_unavailable; KanBot+safe runner yoqilganda /sessions 200 (leveling o'tgan sessiyalari), kill 404 pane_not_found, /etc cwd 422 cwd_outside_project, noma'lum resume 404; begona Origin 403.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
api/ paketi qo'shildi: health, projects (CRUD+summary), board, task detail/create/status/labels, sessions (jonli+o'tgan), new session, resume, kill; barcha xatolar {code, params, detail} formatida. Hub loyiha bo'yicha BacklogClient'ni keshlaydi, KanbotClient, StateResolver va SessionService'ni ulaydi. Resume cwd'ni KanBot ro'yxatidan oladi, loyihadan tashqari cwd va runner'da yo'q agent rad etiladi. Tekshiruv: tests/api da 34 ta test (mock backlog CLI + respx KanBot), make check yashil (379 test); jonli sinovda KanBot o'chiq/yoqiq holatlari va xato kodlari tasdiqlandi.
<!-- SECTION:FINAL_SUMMARY:END -->
