---
id: TASK-53.4
title: 'Popover: "Hover to peek" va hover xatti-harakatini moslash'
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
ordinal: 64000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Popover subtitle "Hover to peek · click to keep open" deydi, lekin `NotchContentView.onPointerEnter/onPointerExit` hech qayerda ulanmagan va `schedulePopoverClose` chaqirilmaydi — popover faqat bosish bilan ochiladi. `popoverPinned` mantigʻi ham shu sababli amalda ishlamaydi. Interfeys va xatti-harakat bir-biriga mos boʻlishi kerak.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Yoki hover haqiqatan ishlaydi (kursor island ustiga kelganda kichik kechikish bilan ochiladi, chiqib ketganda ~0.6s dan keyin yopiladi, bosish pin qiladi), yoki matn va oʻlik kod (pinned/hover) olib tashlanadi — tanlov task notesda asoslanadi
- [ ] #2 Subtitle matni haqiqiy xatti-harakatni tasvirlaydi
- [ ] #3 Island sudrab koʻchirilganda popover tasodifan ochilmaydi
- [ ] #4 Usage regressiyasi tanlangan xatti-harakatni tekshiradi
<!-- AC:END -->
