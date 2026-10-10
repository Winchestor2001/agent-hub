---
id: TASK-53.9
title: 'Popover: maʼlumot shovqinini kamaytirish va qayta tiklanishgacha qolgan vaqt'
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
ordinal: 69000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Popoverda "LIMIT UNAVAILABLE" bir kartada 6 martagacha takrorlanadi; "924 managed files" va "LOCAL" belgisi limit kartasi uchun foydasiz. Barcha yozuvlar katta harfli monospace — oʻqish qiyin. Qayta tiklanish vaqti absolyut ("RESET 6:43 PM") koʻrsatiladi, holbuki `resetCountdown` yozilgan, lekin ishlatilmaydi.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Ikkala oyna ham mavjud boʻlmagan akkaunt uchun bitta qisqa qator chiqadi (masalan, "Limit hali maʼlum emas")
- [ ] #2 Managed files soni va LOCAL/OFFLINE belgisi popoverdan olib tashlanadi (kerak boʻlsa Settings da qoladi)
- [ ] #3 Captionlar oddiy registr va proporsional shriftda, raqamlar monospacedDigit
- [ ] #4 Reset nisbiy vaqtda ("2s 15d qoldi"), absolyut vaqt tooltipda
- [ ] #5 Popover snapshot regressiyasi yangilanadi va rasm koʻrib chiqiladi
<!-- AC:END -->
