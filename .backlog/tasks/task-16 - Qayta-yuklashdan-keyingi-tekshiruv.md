---
id: TASK-16
title: Qayta yuklashdan keyingi tekshiruv
status: Done
assignee:
  - '@claude'
created_date: '2026-09-15 07:27'
updated_date: '2026-09-15 11:49'
labels: []
milestone: m-1
dependencies:
  - TASK-15
ordinal: 16000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Yakuniy qabul: reboot'dan keyin terminalsiz ishlashi.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Reboot (yoki logout/login) dan keyin http://127.0.0.1:8700 ishlaydi, runner claude va codex'ni e'lon qiladi, shell yo'q
- [x] #2 Claude pane'da state_source=hook; Leveling hisoblagichlari to'g'ri
- [x] #3 Xavfsizlik: begona Origin → 403, lsof faqat 127.0.0.1, auto_approve=false
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. make install (real, 8700/8787), make status.
2. AC#1: /api/health ok, runner agents claude+codex, shell yo'q.
3. AC#3: begona Origin → 403 (Agent Hub va KanBot), lsof faqat 127.0.0.1, auto_approve=false (config va runner).
4. AC#2: Agent Hub loyihasida Claude sessiyasi (zararsiz prompt), pane state_source=hook; Leveling hisoblagichlari backlog CLI bilan solishtiriladi; pane to'xtatiladi.
5. Foydalanuvchi logout/login qiladi; keyin 1–3 qayta tekshiriladi, PID'lar yangiligi tasdiqlanadi.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Logout'dan oldin (2026-09-15): make install o'rnatdi (pid 38842/38845/38848), make status exit 0; health ok, runner capabilities [claude, codex], shell yo'q; begona Origin/Host → 403 (8700 va 8787); lsof: 8700 va 8787 faqat 127.0.0.1; auto_approve config=false, runner=0. Leveling: Agent Hub summary total=0, backlog task list ham 'No tasks found' — mos.

Agent Hub loyihasi (foydalanuvchi ruxsati bilan) POST /api/projects orqali registrga qo'shildi. Claude sessiyasi (pane 1a996133, zararsiz prompt): KanBot state=idle state_source=hook, Agent Hub approximate=false. Agent Hub summary To Do 3 / In Progress 1 / Done 15 = backlog task list; active_sessions=1. Pane kill → alive=false. Qolgan: logout/login'dan keyin AC#1 va AC#3 ni qayta tekshirish.

Reboot'dan keyin (boot 2026-09-15 16:36:56, login 16:37): launchd servislarni 16:37:34 da yangi PID'lar bilan ko'tardi (runner 1000, server 1001, backend 1004); make status exit 0 — health ok, 1 runner onlayn, auto_approve config=false runner=false. lsof: 8787 (1001) va 8700 (1004) faqat 127.0.0.1. Qolgan: curl bilan capabilities [claude, codex]/shell yo'q va begona Origin/Host → 403 qayta tekshiruvi (auto mode klassifikatori localhost curl'ni blokladi).

Reboot'dan keyin foydalanuvchi o'z terminalida curl bilan tekshirdi: /api/health 200 ok, kanbot reachable, runners_online=1, agents [claude, codex]; /api/runners capabilities [claude, codex] (shell yo'q), status online, auto_approve=0, last_seen boot'dan keyin. Begona Origin → 403 va begona Host → 403 (8700 va 8787). UI ildizi (/) reboot'dan keyin alohida so'ralmadi; backend va health ishlayapti.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
MVP yakuniy qabuli: servislar make install bilan launchd'ga o'rnatildi va haqiqiy reboot'dan keyin (boot 16:36:56) terminalsiz, yangi PID'lar bilan avtomatik ko'tarildi. AC#1: health ok, runner claude+codex, shell yo'q. AC#2 (reboot'dan oldin): Claude pane state_source=hook, Leveling hisoblagichlari backlog CLI bilan mos. AC#3: begona Origin/Host → 403 (8700, 8787), lsof faqat 127.0.0.1, auto_approve config/runner=false. Dalillar: make status exit 0, lsof, curl natijalari.
<!-- SECTION:FINAL_SUMMARY:END -->
