---
id: TASK-2
title: KanBot himoya launcher'i va xavfli agentlarni o'chirish
status: Done
assignee:
  - '@claude'
created_date: '2026-09-15 07:27'
updated_date: '2026-09-15 07:49'
labels:
  - backend
milestone: m-0
dependencies:
  - TASK-1
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
KanBot'da CORS * va auth yo'q. scripts/kanbot_guarded_server.py KanBot venv python'ida create_app() ni Host/Origin middleware bilan o'raydi (KanBot fayllari o'zgarmaydi). shell, glm, kimi agentlari ~/.kanbot/config.json dagi disabled_agents orqali o'chiriladi (kanbot config --disable, avval diff ko'rsatiladi). /api/health shell o'chirilganini tekshiradi.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Begona Origin'dan HTTP (POST /api/panes/start) va WS /ws/web so'rovlari 403 oladi; Origin'siz so'rovlar, runner va KanBot UI ishlaydi; testlar bor
- [x] #2 disabled_agents = shell, glm, kimi — diff foydalanuvchiga ko'rsatilib, tasdiqdan keyin kanbot config --disable orqali yozilgan
- [x] #3 Agent Hub /api/health: runner capabilities va config'da shell yoqilgan bo'lsa ok=false va aniq ogohlantirish; testlar bor
- [x] #4 make dev KanBot serverni himoya launcher'i orqali ishga tushiradi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. scripts/kanbot_guarded_server.py — faqat stdlib + uvicorn (KanBot venv'ida ishlaydi, agent_hub'ni import qilmaydi): toza ASGI HostOriginGuard (http + websocket, lifespan o'tadi). Host allowlist: 127.0.0.1/localhost/[::1] + port (DNS rebinding). Origin bo'lsa faqat http://127.0.0.1:<port> / http://localhost:<port> (+ --allow-origin); begona yoki 'null' -> HTTP 403 / WS close 1008 (http.response 403). Origin'siz so'rovlar (runner, CLI, Agent Hub backend) o'tadi.
2. main(): kanbot.server.app.create_app(db) ni o'rab uvicorn.run (host faqat loopback, --port, --db, --log-level, access log o'chiq).
3. tests/test_kanbot_guard.py: importlib orqali skriptni yuklab, Starlette dummy app bilan HTTP/WS/preflight/Host testlari.
4. Integratsion test (opt-in): KanBot venv python bilan vaqtinchalik KANBOT_HOME da launcher'ni ishga tushirib, evil Origin POST /api/panes/start -> 403, Origin'siz /api/health -> 200.
5. agent_hub/kanbot_client.py minimal (health, runners; TASK-5 da kengayadi) + agent_hub/kanbot_safety.py: ~/.kanbot/config.json ni faqat o'qib disabled_agents va auto_approve ni tekshirish, online runner capabilities'da shell/glm/kimi yo'qligi.
6. /api/health: kanbot {reachable, version}, safety {ok, problems[]}; ok=false va aniq kod (shell_enabled, agent_enabled, auto_approve_enabled, kanbot_unavailable) — respx testlari.
7. Makefile dev-kanbot -> himoya launcher'i; README yangilash.
8. Jonli tekshiruv: make dev-kanbot + dev-runner, curl evil Origin -> 403, KanBot UI (Origin 8787) ishlaydi, runner ulanadi, capabilities'da shell yo'q, Agent Hub /api/health ok.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Qarorlar: /api/health javobi {ok, version, kanbot{url,reachable,version,runners_online,agents}, problems[{code,severity,params}]} — plan 6-banddagi safety{} o'rniga severity bilan tekis problems ro'yxati (error -> ok=false; no_runner, multiple_runners, kanbot_config_missing — warning). kanbot_safety config.json ni faqat o'qiydi, KANBOT_HOME ni hisobga oladi. AC#4: dev-rejimda KanBot 'make dev-kanbot' orqali ishga tushadi (KANBOT_PYTHON = kanbot venv python, 'command -v kanbot' dan).

Tekshiruv: make check yashil (ruff, mypy --strict, eslint, tsc, pytest 37 passed); pytest -m integration 6 passed. Jonli: make dev-kanbot + make dev-runner -> runner capabilities [claude, codex], auto_approve 0; evil Origin POST /api/panes/start 403, preflight 403, evil Host 403, WS /ws/web evil Origin 403, /api/provider-keys evil 403; o'z origin GET / 200, /api/panes 200, WS /ws/web ulandi; Origin'siz /api/health 200; lsof faqat 127.0.0.1:8787. Agent Hub /api/health ok=true, problems=[]; KANBOT_HOME nusxasida shell yoqilganda ok=false, shell_enabled (source=config). Jarayonlar to'xtatildi.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
scripts/kanbot_guarded_server.py KanBot create_app() ni toza ASGI Host/Origin guard bilan o'raydi (begona Host/Origin -> HTTP 403 / WS 1008->403; Origin'siz mijozlar o'tadi), make dev-kanbot shu launcher'ni ishlatadi, README dev-rejim yangilandi. shell/glm/kimi kanbot config --disable orqali o'chirildi (diff tasdiqdan keyin). Agent Hub'ga minimal kanbot_client (health, runners) va kanbot_safety qo'shildi; /api/health config va online runner'larda shell/glm/kimi hamda auto_approve ni tekshiradi, xato bo'lsa ok=false va kodli problems. Tekshiruv: 18 guard unit, 10 health respx, 6 jonli integratsion test; make check yashil; haqiqiy KanBot+runner bilan curl/WS jonli tekshiruvi.
<!-- SECTION:FINAL_SUMMARY:END -->
