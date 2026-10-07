---
id: TASK-39.2
title: Desktop controls and notifications
status: Done
assignee:
  - '@codex'
created_date: '2026-09-28 06:33'
updated_date: '2026-09-29 06:56'
labels:
  - desktop
  - client
dependencies:
  - TASK-39.1
parent_task_id: TASK-39
type: feature
ordinal: 45000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
MVP .app oynasi ishlagandan keyin desktopga xos qulayliklar qo‘shiladi: menu/status item, restart/open logs/open browser kabi servis amallari va brauzer bildirishnomalaridan mustaqil native notification oqimi.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Menu yoki status item orqali Agent Hub oynasini ochish/yashirish mumkin
- [x] #2 App servis holatini ko‘rsatadi va restart/open logs kabi amallarni xavfsiz bajaradi
- [x] #3 Native notification oqimi mavjud web bildirishnomalariga zid kelmaydi
- [x] #4 Desktop controls uchun test yoki qo‘lda tekshiruv eslatmalari yozilgan
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. macOS wrapper'dagi Swift/AppKit tuzilmasini tekshirish: app lifecycle, WKWebView, backend URL/offline handling.\n2. Status/menu bar item qo'shish: Agent Hub oynasini show/hide qilish va quit amali.\n3. Desktop servis control'larini xavfsiz boshlash: app ichida service health ko'rsatish, browser/log ochish va restart uchun aniq cheklangan handlerlar.\n4. Native notification oqimini web notification bilan konflikt qilmaydigan minimal bridge sifatida qo'shish yoki chegarasini hujjatlash.\n5. Swift build, make macos-app va make check bilan tekshirish; qo'lda test uchun qisqa checklist yozish.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented first desktop controls slice in macOS wrapper: status bar item with backend status, show/hide window, check status, open in browser, open logs folder, copy install command, and service restart/update via visible Terminal make install command. Native notifications are limited to desktop service events (offline/online and restart command opened), so they do not duplicate web session/block notifications. Verification: swift build --package-path macos/AgentHubApp passed; make macos-app passed. Manual QA checklist: open app, verify menu bar/status item appears, hide/show window works, Check Status reloads health, Open Logs opens ~/Library/Logs/agent-hub, Open in Browser opens configured URL, Restart/Update Services opens Terminal with make install, offline/online state updates status title.

Warning cleanup: notification permission prompt is lazy and only requested when a desktop service notification is actually sent. Fresh verification after cleanup: swift build --package-path macos/AgentHubApp passed without warnings; make macos-app passed; make check passed earlier in this slice with 635 pytest and 124 vitest.

Manual verification from user: status item/menu controls worked in Agent Hub.app. Fresh automated verification before completion: swift build --package-path macos/AgentHubApp passed; make check passed with 635 pytest selected passing and 124 vitest passing.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented macOS desktop controls: status bar menu for show/hide, health check, browser/log opening, safe service restart/update through visible Terminal make install command, and desktop service notifications separated from web session notifications. Verified by user manual test plus fresh swift build and make check.
<!-- SECTION:FINAL_SUMMARY:END -->
