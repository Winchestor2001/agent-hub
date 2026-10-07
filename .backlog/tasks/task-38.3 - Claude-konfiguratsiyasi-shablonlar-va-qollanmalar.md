---
id: TASK-38.3
title: 'Claude konfiguratsiyasi: shablonlar va qo''llanmalar'
status: Done
assignee:
  - '@claude'
created_date: '2026-09-24 16:38'
updated_date: '2026-10-07 11:18'
labels: []
dependencies:
  - TASK-38.2
parent_task_id: TASK-38
ordinal: 41000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Foydalanuvchi skill, agent, command, rule, hook va settings yozish qoidalarini eslab qolishi shart bo'lmasin: har tur uchun o'zbekcha qo'llanma (global yoki bitta yoki bir nechta loyiha uchun qanday yozish, ustuvorlik va yopilish qoidalari) va tayyor namunalar kerak. Foydalanuvchi o'z .md yoki .json faylini ham qo'sha olishi kerak.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 src/agent_hub/templates/claude/ da har tur uchun kamida bitta shablon bor (skill, command, agent, rule, CLAUDE.md, settings, hook skripti) va u paket build'iga kiradi
- [x] #2 API shablonlar va qo'llanmalar ro'yxatini hamda matnini qaytaradi
- [x] #3 O'zbekcha qo'llanmalar skill uchun global, bitta loyiha va bir nechta loyiha holatlarini tushuntiradi; ustuvorlikni (skill: Personal ustun, agent: Project ustun, settings: local > project > user) va CLAUDE.local.md ni gitignore'ga qo'shish ogohlantirishini o'z ichiga oladi
- [x] #4 Foydalanuvchi o'z md/json matnini yuborib, uni tanlangan qamrovga mavjud yozish xavfsizligi qoidalari orqali saqlay oladi
- [x] #5 Har bir shablon o'z turi validatsiyasidan o'tishi testda tekshiriladi; pytest yashil
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. src/agent_hub/templates/claude/: shablonlar (skill, command, agent, rule, CLAUDE.md, CLAUDE.local.md, settings, settings.local, .mcp.json, hook skripti) — {{name}} o'rinbosari bilan; guides/*.md o'zbekcha qo'llanmalar (umumiy, skills, agents, commands, rules, CLAUDE.md, settings, hooks, mcp).
2. services/claude_templates.py: katalog (id, kind, default nom, fayl), render(id, name) nomni regex bilan tekshirib o'rniga qo'yadi; qo'llanmalar katalogi (id, sarlavha birinchi # dan, turlar).
3. API: GET /api/claude-config/templates, /templates/{id}?name=, /guides, /guides/{id}.
4. Foydalanuvchi o'z matni: mavjud PUT/apply orqali (yangi endpoint emas) — test bilan.
5. Testlar: har shablon o'z turi validatsiyasidan o'tadi, qo'llanmalarda ustuvorlik va gitignore ogohlantirishi bor, wheel build'ida fayllar bor.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Shablonlar: skill, command, agent, rule, CLAUDE.md, CLAUDE.local.md, settings, settings.local, settings+hook ro'yxati, .mcp.json, hook skripti (guard-bash.sh). {{name}} o'rinbosari render'da tur qoidasidan o'tgan nom bilan almashtiriladi. Qo'llanmalar (uz): overview, skills, agents, commands, rules, claude-md, settings, hooks, mcp. Foydalanuvchi o'z matni alohida endpoint emas — mavjud PUT/apply orqali o'sha validatsiya bilan saqlanadi (UI fayl o'qishni brauzerda qiladi).
Tekshiruv: tests/test_claude_templates.py — har shablon o'z turi validate() dan o'tadi, har turga shablon va qo'llanma bor, qo'llanmalarda 'Personal (global) ustun', 'Project (loyiha) ustun', 'local > project > user', CLAUDE.local.md gitignore matni; hook shabloni haqiqiy sh bilan: oddiy buyruq 0, 'git push --force' 2 + stderr. Integratsiya testi: uv build --wheel ichida barcha shablon va qo'llanma fayllari bor (pytest -m integration, o'tdi). API testlari: templates/guides endpoint'lari va o'z matnini PUT/apply qilish. pytest 736 passed, ruff, mypy toza.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
src/agent_hub/templates/claude/ (11 shablon + 9 o'zbekcha qo'llanma), services/claude_templates.py va GET /api/claude-config/templates[/id], /guides[/id] qo'shildi. Har shablon validatsiyadan o'tishi, qo'llanma mazmuni, hook skripti xatti-harakati va wheel tarkibi testlar bilan tekshirildi.
<!-- SECTION:FINAL_SUMMARY:END -->
