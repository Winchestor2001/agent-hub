---
id: TASK-53.5
title: 'Island: nomaʼlum usage uchun 100% chiziq va "0% / nomaʼlum" farqi'
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
type: bug
ordinal: 65000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`compactProviderCell` Claude usage nomaʼlum, lekin konfiguratsiya mavjud boʻlsa status barni `progress = 1` bilan toʻla chizadi — bu "limit tugadi" deb oʻqiladi. Codex limitlarini oʻqib boʻlmaganda halqa boʻsh qoladi va 0% bilan farqlanmaydi (skrinshotda Codex halqasi aynan shunday). Limit monitori uchun nomaʼlum holat aniq koʻrinishi shart.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Usage nomaʼlum boʻlsa hech qachon toʻla yoki deyarli toʻla chiziq/halqa chizilmaydi
- [ ] #2 Nomaʼlum/oʻqib boʻlmagan holat 0% dan vizual farq qiladi (masalan, punktir halqa yoki "—"), yuklanish holati esa alohida
- [ ] #3 Tooltipda nima uchun nomaʼlumligi (yuklanmoqda / CLI topilmadi / maʼlumot hali yoʻq) yoziladi
- [ ] #4 Regressiya: Claude usage nil + konfiguratsiya mavjud holatda progress 1 emas
<!-- AC:END -->
