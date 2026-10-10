---
id: TASK-53.11
title: Codex limitlarini soʻrash intervalini kamaytirish
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
priority: medium
type: enhancement
ordinal: 71000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`CodexUsageReader` har 4 soniyada yangi `codex app-server` jarayonini ishga tushiradi (ichida 1s sleep va 2s timeout). Bu batareya va CPU uchun ogʻir, limitlar esa bunchalik tez oʻzgarmaydi. Claude keshi lokal fayl boʻlgani uchun tez oʻqilishi mumkin.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Codex soʻrovi fon rejimida 30–60s intervalda, popover ochilganda va Refresh bosilganda darhol bajariladi
- [ ] #2 Claude lokal keshi tezroq (masalan, 4–5s) oʻqilaverishi mumkin va Codex soʻroviga bogʻliq emas
- [ ] #3 Bir vaqtda bittadan ortiq Codex jarayoni ishlamaydi
- [ ] #4 Usage regressiyasidagi interval tekshiruvi yangi qiymatlarga moslashtiriladi
<!-- AC:END -->
