---
id: TASK-13
title: launchd shablonlari
status: Done
assignee:
  - '@claude'
created_date: '2026-09-15 07:27'
updated_date: '2026-09-15 10:52'
labels:
  - backend
milestone: m-1
dependencies:
  - TASK-12
ordinal: 13000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
3 ta plist shabloni: kanbot-server (himoya launcher'i), kanbot-runner (--safe), backend. PATH, ProcessType, WorkingDirectory, loglar.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Render qilingan plist'lar plutil -lint dan o'tadi
- [x] #2 PATH real papkalarni o'z ichiga oladi; RunAtLoad, KeepAlive, ThrottleInterval; loglar ~/Library/Logs/agent-hub/
- [x] #3 runner --safe bilan; plist'larda API kalitlar yoki tokenlar yo'q
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. launchd/ ichida 3 ta plist shabloni (@PLACEHOLDER@): kanbot-server (KanBot venv python + scripts/kanbot_guarded_server.py), kanbot-runner (kanbot runner --safe), backend (.venv python -m agent_hub).
2. scripts/render_launchd.py (faqat stdlib): yo'llarni aniqlaydi (repo, kanbot, KanBot python, .venv python), real PATH yig'adi, XML-escape bilan render qiladi, qolgan placeholder'larni va plistlib parse'ni tekshiradi, --out papkaga yozadi. Tokenlarni o'qimaydi.
3. Hammasi: RunAtLoad, KeepAlive, ThrottleInterval, ProcessType, WorkingDirectory, EnvironmentVariables (PATH, LANG, PYTHONUNBUFFERED), loglar ~/Library/Logs/agent-hub/<servis>.log.
4. tests/test_launchd.py: render, plutil -lint, PATH/kalitlar/--safe, token yo'qligi, escape.
5. launchd'ga haqiqiy o'rnatish yo'q (TASK-14). make check.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Qo'shildi: launchd/{kanbot-server,kanbot-runner,backend}.plist.in (@PLACEHOLDER@) va scripts/render_launchd.py (stdlib). Label'lar local.agent-hub.<servis>, fayl nomi <label>.plist.

- kanbot-server: uv tool KanBot venv python'i + scripts/kanbot_guarded_server.py --port; runner: kanbot runner --safe --server http://127.0.0.1:<port>; backend: <repo>/.venv/bin/python -m agent_hub (uv run emas: ishga tushishda sync qilmaydi), AGENT_HUB_PORT va AGENT_HUB_KANBOT_URL env orqali.
- Hammasida RunAtLoad, KeepAlive, ThrottleInterval=10, ProcessType=Standard, WorkingDirectory (runner uchun HOME), PATH/LANG/PYTHONUNBUFFERED, stdout+stderr ~/Library/Logs/agent-hub/<servis>.log.
- PATH: topilgan kanbot/claude/codex/backlog/node/uv/git papkalari, ~/.local/bin, /opt/homebrew/{bin,sbin}, /usr/local/bin, keyin tizim papkalari; faqat mavjud papkalar, takrorsiz.
- Renderer tokenlarni o'qimaydi; qiymatlar XML-escape qilinadi, noma'lum placeholder va o'qilmaydigan plist xato beradi; check_context portlar, label va bajariladigan fayllarni tekshiradi.
- Log papkasini yaratish va launchctl bootstrap TASK-14 ga qoldi.

Tekshiruv: tests/test_launchd.py (10 test, plutil -lint ham); haqiqiy mashinada render + plutil -lint 3/3 OK, ~/.kanbot/config.json dagi maxfiy qiymatlar plist'larda yo'q; env -i va plist PATH bilan server+backend alternativ portlarda ishga tushib /api/health ok qaytardi; make check yashil (pytest 415, vitest 40).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
3 ta LaunchAgent shabloni (kanbot-server himoya launcher'i bilan, kanbot-runner --safe, backend) va ularni joriy mashina yo'llari bilan render qiluvchi scripts/render_launchd.py qo'shildi. Render qilingan plist'lar plutil -lint dan o'tadi, real PATH, RunAtLoad/KeepAlive/ThrottleInterval/ProcessType va ~/Library/Logs/agent-hub/ loglari bor, token yoki API kalit yo'q. launchd'ga o'rnatish, log papkasi va make target'lari TASK-14 da.
<!-- SECTION:FINAL_SUMMARY:END -->
