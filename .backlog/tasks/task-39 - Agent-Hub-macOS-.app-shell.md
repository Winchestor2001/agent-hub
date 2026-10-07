---
id: TASK-39
title: Agent Hub macOS .app shell
status: Done
assignee:
  - '@codex'
created_date: '2026-09-28 06:29'
updated_date: '2026-10-07 10:37'
labels:
  - desktop
  - client
dependencies: []
type: feature
ordinal: 43000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Web UI brauzerda ishlaganda focus, notification, shortcut, localhost/tab holati va terminal tajribasi kabi mayda muammolar chiqyapti. Maqsad mavjud FastAPI backend va React UI ni tashlab yubormasdan, ularni macOS .app ichida barqaror desktop tajribaga o‘rash; keyingi yangi featurelar shu asos ustiga qo‘shiladi.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Agent Hub brauzer tabsiz macOS .app oynasida ochiladi
- [x] #2 Backend ishlamayotgan bo‘lsa app foydalanuvchiga tushunarli status va qayta urinish yo‘lini ko‘rsatadi
- [x] #3 Mavjud backend/API/frontend arxitekturasi saqlanadi, katta rewrite qilinmaydi
- [x] #4 Desktop qulayliklar va keyingi featurelar alohida subtasllarga ajratilgan
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. MVP WKWebView wrapper (TASK-39.1). 2. Desktop controls va bildirishnomalar (TASK-39.2). 3. Packaging, icon, release zip va autostart hujjati (TASK-39.3). 4. Subtasklar dalillari asosida parent AC'larni tekshirish.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Parent yakuni (2026-10-07): AC #1 va #2 TASK-39.1 dagi foydalanuvchi qo'lda tekshiruvi (online oyna, offline xato ekrani) bilan tasdiqlangan; AC #3: backend/API/frontend o'zgarmagan, faqat macos/AgentHubApp wrapper va build skriptlari qo'shilgan; AC #4: 39.1-39.3 subtasklari Done. Qayta tekshiruv: swift build --package-path macos/AgentHubApp o'tdi, make check yashil (pytest 643, vitest 124).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Agent Hub mavjud FastAPI+React arxitekturasini o'zgartirmasdan macOS .app (WKWebView) ichiga o'raldi: status menu, servis boshqaruvi, icon va release zip. Subtasklar 39.1-39.3 Done; swift build va make check yashil.
<!-- SECTION:FINAL_SUMMARY:END -->
