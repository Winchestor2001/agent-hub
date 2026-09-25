---
id: TASK-38.3
title: 'Claude konfiguratsiyasi: shablonlar va qo''llanmalar'
status: To Do
assignee: []
created_date: '2026-09-24 16:38'
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
- [ ] #1 src/agent_hub/templates/claude/ da har tur uchun kamida bitta shablon bor (skill, command, agent, rule, CLAUDE.md, settings, hook skripti) va u paket build'iga kiradi
- [ ] #2 API shablonlar va qo'llanmalar ro'yxatini hamda matnini qaytaradi
- [ ] #3 O'zbekcha qo'llanmalar skill uchun global, bitta loyiha va bir nechta loyiha holatlarini tushuntiradi; ustuvorlikni (skill: Personal ustun, agent: Project ustun, settings: local > project > user) va CLAUDE.local.md ni gitignore'ga qo'shish ogohlantirishini o'z ichiga oladi
- [ ] #4 Foydalanuvchi o'z md/json matnini yuborib, uni tanlangan qamrovga mavjud yozish xavfsizligi qoidalari orqali saqlay oladi
- [ ] #5 Har bir shablon o'z turi validatsiyasidan o'tishi testda tekshiriladi; pytest yashil
<!-- AC:END -->
