---
id: TASK-53.12
title: 'Settings oynasi: native sidebar, Accounts sahifasi va takroriy kartalar'
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
priority: low
type: enhancement
ordinal: 72000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Settings sidebari `texturedRounded` tugmalardan iborat, tanlangan holat faqat rang bilan bildiriladi — macOS uchun native koʻrinmaydi. "Accounts" sahifasida faqat boshqa oynani ochadigan bitta tugma bor (ortiqcha qadam). Codex da "Settings" va "MCP" kartalari bir xil `config.toml` ni ochadi. Sidebar pastidagi "Every future edit will be backed up..." matni ham gʻalati yozilgan.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Sidebar source list uslubida (NSOutlineView/NSTableView .sourceList yoki ekvivalent), tanlangan qator native highlight bilan
- [ ] #2 Accounts sahifasi akkauntlar holatini (nom, holat, usage) shu yerda koʻrsatadi yoki sidebar elementi toʻgʻridan-toʻgʻri Accounts oynasini ochadi
- [ ] #3 Codex da bir faylga ikki karta qolmaydi (birlashtiriladi yoki MCP kartasi faqat MCP boʻlimiga sakraydi)
- [ ] #4 Backup haqidagi matn aniq va toʻgʻri
- [ ] #5 Settings regressiyasi yangilanadi va oʻtadi
<!-- AC:END -->
