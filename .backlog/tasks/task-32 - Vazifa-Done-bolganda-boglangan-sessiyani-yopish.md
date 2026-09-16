---
id: TASK-32
title: Vazifa Done bo'lganda bog'langan sessiyani yopish
status: Done
assignee:
  - '@claude'
created_date: '2026-09-16 06:49'
updated_date: '2026-09-16 06:55'
labels:
  - client
dependencies: []
ordinal: 32000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Vazifa In Progress'ga o'tganda sessiya dialogi ochiladi, lekin teskarisi yo'q: vazifa Done bo'lgach unga bog'langan agent pane'i ochiq qolaveradi. Foydalanuvchi uni UI orqali umuman yopa olmaydi — hozir faqat tugagan sessiyani ro'yxatdan olib tashlash va transkriptni o'chirish bor, jonli pane'ni to'xtatish tugmasi yo'q (backendda POST /api/sessions/{pane_id}/kill bor, frontend ishlatmaydi). Natijada bo'sh agentlar runner'da yig'ilib qoladi. Foydalanuvchi tanlovi: tasdiq so'raladigan variant (ishlab turgan agent tasodifan o'ldirilmasin) va faqat frontend qamrovi — doskadagi drag'n'drop ham, vazifa oynasidagi status select ham BoardView.statusChanged orqali o'tadi.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Vazifa config'dagi oxirgi statusga o'tkazilganda va unda tirik sessiya bo'lsa, doskada tasdiq so'rovi chiqadi (nechta sessiya yopilishi ko'rsatiladi)
- [x] #2 Tasdiqlansa har bir pane POST /api/sessions/{pane_id}/kill bilan yopiladi, xato bo'lsa dialogda ko'rinadi; bekor qilinsa hech narsa yopilmaydi
- [x] #3 Tirik sessiyasi yo'q vazifa yoki boshqa statusga o'tish hech qanday so'rov chiqarmaydi
- [x] #4 So'rov doskadan (drag'n'drop) ham, vazifa oynasidagi status tanlovidan ham ishlaydi
- [x] #5 Yangi matnlar uz va ru lug'atlarida bor, web testlari (model + i18n) o'tadi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. board/model.ts: sessionsToClose(task, status, statuses) — status config'dagi oxirgi bo'lsa, task.sessions dan alive bo'lganlarini qaytaradi; testlar.
2. api/queries.ts: useKillSessions() — har pane uchun POST /api/sessions/{id}/kill, pane_not_found yutiladi, onSettled da useInvalidateSessions.
3. BoardPanel/BoardView: statusChanged'da shouldOpenSession bo'lmasa sessionsToClose tekshiriladi va confirm state qo'yiladi; SessionsPanel'dagi .confirm namunasidek inline alertdialog (bekor / yopish, xato ErrorText).
4. i18n uz+ru: board.close_session*, board.closing kalitlari.
5. npm test + typecheck + lint; TASK-29 WIP'ga tegmasdan faqat o'z hunk'larim commit qilinadi.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Bajarildi: model.ts'da isDoneStatus + sessionsToClose (groupByStatus ham isDoneStatus'ga o'tdi), queries.ts'da useKillSessions (POST /api/sessions/{id}/kill, pane_not_found yutiladi, onSettled — sessiyalar/doska/loyihalar invalidatsiyasi), BoardPanel'da statusChanged tugagan statusda tasdiq blokini ochadi (.confirm, role=alertdialog), uz+ru lug'atlariga board.close_session* kalitlari.

Tekshiruv: npm test 92 test yashil (shu jumladan sessionsToClose uchun 3 ta yangi test), typecheck va lint toza. Backend yo'li jonli hub'da tekshirildi: POST /api/sessions/yoq-pane/kill → 404 pane_not_found (hook aynan shu kodni yutadi). Frontend build src/agent_hub/static ga qilindi, bundle'da yangi matnlar bor.

Qolgan: dialogni brauzerda ko'z bilan tekshirish — Claude in Chrome kengaytmasi ulanmagani uchun men bajara olmadim, foydalanuvchi 8700 ni yangilab sinaydi.

Foydalanuvchi 8700 dagi ilovada tekshirdi: vazifa Done qilinganda tasdiq so'rovi chiqadi va ishlaydi.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Vazifa config'dagi oxirgi statusga o'tkazilganda, unga bog'langan tirik agent pane'lari bo'lsa, doskada tasdiq so'raladi; tasdiqlansa har bir pane POST /api/sessions/{id}/kill bilan yopiladi (pane_not_found yutiladi), bekor qilinsa hech narsa o'zgarmaydi. Doska drag'n'drop'i va vazifa oynasidagi status tanlovi bitta BoardView.statusChanged orqali o'tgani uchun ikkalasida ham ishlaydi. model.ts: isDoneStatus + sessionsToClose; queries.ts: useKillSessions; BoardPanel: .confirm bloki; uz+ru kalitlari. Tekshiruv: 92 web testi (3 tasi yangi), typecheck, lint toza; jonli hub'da kill endpoint'i 404 pane_not_found qaytarishi tasdiqlandi; UI ni foydalanuvchi brauzerda sinab ko'rdi. Commit: ac44acf.
<!-- SECTION:FINAL_SUMMARY:END -->
