---
id: TASK-53.15
title: 'Island: accessibility (VoiceOver, rangga bogʻliq boʻlmagan holat)'
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
ordinal: 75000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`UsageRingView` va island katakchalarining accessibility label/value yoʻq — VoiceOver foizni oʻqiy olmaydi. Holatlar asosan rang bilan bildiriladi. Popover va kartalar oʻlchamlari qattiq piksellarda (356/324/296) belgilangan.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Island katakchalari VoiceOver da "Claude, 5 soatlik limit 47%, ..." kabi oʻqiladi; popover tugmalari va kartalari ham nomlangan
- [ ] #2 Har bir holat (nomaʼlum, ogohlantirish, xavf, eskirgan) rangdan tashqari matn yoki belgi bilan ham bildiriladi
- [ ] #3 Increase Contrast va Reduce Motion sozlamalari hurmat qilinadi
- [ ] #4 Accessibility Inspector bilan qoʻlda tekshiruv natijasi task notesda
<!-- AC:END -->
