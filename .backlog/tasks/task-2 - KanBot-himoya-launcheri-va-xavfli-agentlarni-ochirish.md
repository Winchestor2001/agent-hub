---
id: TASK-2
title: KanBot himoya launcher'i va xavfli agentlarni o'chirish
status: To Do
assignee: []
created_date: '2026-09-15 07:27'
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
- [ ] #1 Begona Origin'dan HTTP (POST /api/panes/start) va WS /ws/web so'rovlari 403 oladi; Origin'siz so'rovlar, runner va KanBot UI ishlaydi; testlar bor
- [ ] #2 disabled_agents = shell, glm, kimi — diff foydalanuvchiga ko'rsatilib, tasdiqdan keyin kanbot config --disable orqali yozilgan
- [ ] #3 Agent Hub /api/health: runner capabilities va config'da shell yoqilgan bo'lsa ok=false va aniq ogohlantirish; testlar bor
- [ ] #4 make dev KanBot serverni himoya launcher'i orqali ishga tushiradi
<!-- AC:END -->
