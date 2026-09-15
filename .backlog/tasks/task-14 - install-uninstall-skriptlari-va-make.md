---
id: TASK-14
title: install/uninstall skriptlari va make
status: To Do
assignee: []
created_date: '2026-09-15 07:27'
labels:
  - backend
milestone: m-1
dependencies:
  - TASK-13
ordinal: 14000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
scripts/install-services.sh va uninstall-services.sh (idempotent), make install/uninstall/status/logs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 install ikki marta ishga tushirilganda xato bermaydi va o'zgarmagan servisni restart qilmaydi
- [ ] #2 Qo'lda ishlayotgan kanbot up (8787), runner yoki tirik pane'lar bo'lsa ogohlantirib to'xtaydi (--force bilan davom)
- [ ] #3 make status: 3 job holati, health, aynan 1 runner va auto_approve=false; make logs ishlaydi
- [ ] #4 uninstall servislarni to'xtatadi va plist'larni o'chiradi, loglar qoladi
<!-- AC:END -->
