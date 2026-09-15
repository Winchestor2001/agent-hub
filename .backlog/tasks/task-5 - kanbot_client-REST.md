---
id: TASK-5
title: kanbot_client (REST)
status: Done
assignee:
  - '@claude'
created_date: '2026-09-15 07:27'
updated_date: '2026-09-15 08:19'
labels:
  - backend
milestone: m-0
dependencies:
  - TASK-2
  - TASK-3
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
KanBot'ga yagona kirish nuqtasi: httpx.AsyncClient, pydantic modellar (extra=ignore), typed xatolar, versiya tekshiruvi, argv'dan --settings JSON'ni tozalash.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 health, runners, list_panes, get_pane, start_pane, read_pane, send_text, send_keys, kill_pane, remove_pane, list_agent_sessions — respx testlari (refused, 409, 502)
- [x] #2 Noma'lum maydonlar e'tiborsiz; 0.8.x bo'lmagan versiyada ogohlantirish
- [x] #3 argv'dan --settings qiymati olib tashlanadi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Tadqiqot (KanBot 0.8.2 manba kodi): /api/panes -> {panes:[...]} (blocked/working/idle/unknown/done tartibida), pane: id, agent, title, cwd, argv, interactive, session_id, card_id, state, state_source (hook|screen|exit), pid, rows, cols, started_at, last_output_at, ended_at, exit_code, alive, runner_id, runner_name. POST /api/panes/start {agent,prompt,cwd,interactive,resume,title,runner_id} -> pane; 409 (runner/agent yo'q), 502 (runner xatosi/timeout). GET /api/panes/{id} (404), GET /read?lines=N -> {text,pane} (404/502), POST /input {text,enter}|{keys} (404/502), POST /kill (404), DELETE /api/panes/{id} -> {ok}. GET /api/agent-sessions -> {sessions:[{agent,session_id,cwd,name,title,recap,recap_role,last_user,last_text,tail,turns,started_at,mtime,active,runner_id}]}. Xatolar FastAPI {detail}. Runner noma'lum agentda 'shell'ga tushib qolishi mumkin -> klient faqat claude/codex ga ruxsat beradi.
2. Xatolar: KanbotError(message, status, detail) code=kanbot_error; KanbotUnavailable (ulanish/timeout) kanbot_unavailable; KanbotNoRunner (409) kanbot_no_runner; KanbotRunnerError (502) kanbot_runner_error; KanbotPaneNotFound (404) pane_not_found. Mavjud app.py health mos qoladi.
3. Modellar (extra=ignore): Pane (argv validator'da --settings qiymati '{hooks}' bilan almashtiriladi, --settings=... ham), AgentSession (tail/last_* keraksiz katta maydonlar olinmaydi), PaneRead {text, pane}.
4. Metodlar: list_panes, get_pane, start_pane(agent, prompt, cwd, title, resume, runner_id; interactive=True; agent faqat claude|codex, aks holda ValueError), read_pane(id, lines 1..500), send_text(id, text, enter), send_keys(id, keys — faqat ruxsat etilgan tugma nomlari), kill_pane, remove_pane, list_agent_sessions. start_pane uchun uzunroq timeout (runner 15 s kutadi).
5. Versiya: SUPPORTED_VERSION_PREFIX='0.8.'; kanbot_safety.check_version -> kanbot_version_unsupported (warning); /api/health'ga qo'shiladi; klient bir marta log ogohlantirish.
6. Testlar respx bilan: har metod uchun muvaffaqiyat + refused (ConnectError) + 409/502/404 xaritalash, noma'lum maydonlar, --settings tozalash, versiya ogohlantirishi, health endpoint'da versiya muammosi.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- API shakllari KanBot 0.8.2 manba kodidan olindi (server/app.py, server/hub.py, runner/panes.py, runner/worker.py, runner/discovery.py); tests/fixtures/kanbot/ ular asosida.
- Xavfsizlik: start_pane faqat claude/codex qabul qiladi — runner noma'lum agentda 'shell'ga tushib qolishi mumkin (worker.start_pane: agents.get(name) or agents.get('shell')). interactive doim True. send_keys faqat KanBot KEYS nomlari, C-<belgi> va yakka belgi. Pane ID URL'ga faqat [A-Za-z0-9_-]{1,64} bo'lsa qo'yiladi.
- argv'dagi --settings qiymati (hook buyruqlari, python yo'li) '{hooks}' bilan almashtiriladi (--settings=... shakli ham).
- AgentSession'da tail/last_user/last_text olinmaydi (katta va keraksiz).
- kill 404 'pane not found or runner offline' — ikkala holat ham pane_not_found bo'lib keladi (KanBot farqlamaydi).
- Versiya: 0.8.x bo'lmasa klient bir marta log ogohlantiradi, /api/health'da kanbot_version_unsupported (warning).
- Jonli tekshiruv: vaqtinchalik KANBOT_HOME bilan himoyalangan server (port 8791, runner'siz): health 0.8.2, panes/sessions/runners bo'sh, start -> KanbotNoRunner 409, get/read/input -> KanbotPaneNotFound 404, remove ok, yopiq port -> KanbotUnavailable.
- make check yashil: 255 test.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
kanbot_client to'liq REST qatlamiga kengaytirildi: list_panes, get_pane, start_pane (faqat claude/codex, interactive, resume/runner_id, uzun timeout), read_pane (1..500 qator), send_text, send_keys (ruxsat etilgan tugmalar), kill_pane, remove_pane, list_agent_sessions; typed xatolar KanbotUnavailable/KanbotNoRunner(409)/KanbotRunnerError(502)/KanbotPaneNotFound(404)/KanbotError; pydantic modellar noma'lum maydonlarni e'tiborsiz qoldiradi; argv'dagi --settings JSON yashiriladi; 0.8.x bo'lmagan versiyada ogohlantirish (log + health muammosi). Tekshiruv: tests/test_kanbot_client.py (respx: har metod uchun refused/timeout va 409/502/404/500 xaritalash, fixture'lar, tozalash, versiya), test_health.py'ga versiya testi, runner'siz haqiqiy KanBot 0.8.2 ga qarshi jonli skript; make check yashil.
<!-- SECTION:FINAL_SUMMARY:END -->
