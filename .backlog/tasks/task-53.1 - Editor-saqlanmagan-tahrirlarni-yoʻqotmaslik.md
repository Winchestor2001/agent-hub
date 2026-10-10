---
id: TASK-53.1
title: 'Editor: saqlanmagan tahrirlarni yoʻqotmaslik'
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
ordinal: 61000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Konfiguratsiya editorida boshqa fayl tanlanganda yoki oyna yopilganda `loadConfigurationFile` editor matnini hech narsa soʻramay almashtiradi — foydalanuvchi tahriri jimgina yoʻqoladi. Qidiruv qoralamani saqlaydi, fayl tanlash esa saqlamaydi, bu nomuvofiq va xavfli. Saqlash uchun klaviatura yorligʻi ham yoʻq.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Tahrir qilingan, saqlanmagan fayl UIda belgilanadi (masalan, sarlavhada nuqta yoki "Edited" yozuvi, oyna documentEdited holati)
- [ ] #2 Saqlanmagan oʻzgarish bor paytda boshqa fayl tanlash, kategoriya almashtirish yoki oynani yopish Save / Discard / Cancel tanlovini beradi; Cancel tanlov va matnni oʻzgarishsiz qoldiradi
- [ ] #3 ⌘S saqlash oqimini (review + backup) ishga tushiradi
- [ ] #4 Native regressiya: tahrir → boshqa fayl tanlash → Cancel holatida qoralama saqlanib qolishi tekshiriladi
<!-- AC:END -->
