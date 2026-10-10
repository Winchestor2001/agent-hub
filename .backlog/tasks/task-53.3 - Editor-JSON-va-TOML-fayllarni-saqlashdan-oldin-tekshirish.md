---
id: TASK-53.3
title: 'Editor: JSON va TOML fayllarni saqlashdan oldin tekshirish'
status: To Do
assignee: []
created_date: '2026-10-10 15:13'
labels:
  - ai-island
  - ux
dependencies: []
references:
  - macos/AIIslandApp/Sources/AIIslandApp/main.swift
parent_task_id: TASK-53
priority: high
type: enhancement
ordinal: 63000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`settings.json`, `settings.local.json`, `~/.claude.json` va `config.toml` sintaksis xatosi bilan saqlanishi mumkin — shundan keyin Claude Code yoki Codex ishga tushmay qoladi. Backup bor, lekin xatoning oldini olish undan yaxshiroq.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 .json fayllar saqlashdan oldin parse qilinadi; xato boʻlsa qator/ustun bilan aniq xabar chiqadi va fayl yozilmaydi
- [ ] #2 .toml fayllar uchun kamida asosiy sintaksis tekshiruvi bor (yoki xato aniqlansa ogohlantirib, foydalanuvchi ongli ravishda "baribir saqlash"ni tanlashi mumkin)
- [ ] #3 Toʻgʻri fayllar oldingidek review + backup oqimi bilan saqlanadi
- [ ] #4 Testlar: yaroqli va yaroqsiz JSON/TOML namunalari
<!-- AC:END -->
