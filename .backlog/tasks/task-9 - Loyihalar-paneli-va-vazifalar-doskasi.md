---
id: TASK-9
title: Loyihalar paneli va vazifalar doskasi
status: Done
assignee:
  - '@claude'
created_date: '2026-09-15 07:27'
updated_date: '2026-09-15 09:39'
labels:
  - client
  - backend
milestone: m-0
dependencies:
  - TASK-7
  - TASK-8
ordinal: 9000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Chap panel: loyihalar hisoblagichlari, qo'shish/o'chirish. Markaz: status ustunlari, filtrlar, kartochkalar, detal panel, CLI orqali mutatsiyalar.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Loyiha hisoblagichlari (To Do/In Progress/Done, bug, faol sessiyalar, blocked) backlog task list --json ga mos
- [x] #2 Label (backend/admin/client/bug) va milestone filtrlari; kartochkada ID, sarlavha, labellar, ijrochi, AC va DoD progress
- [x] #3 Detal panel: tavsif, plan, notes, bog'liqliklar, subtask'lar
- [x] #4 Vazifa yaratish, status o'zgartirish, label qo'shish CLI orqali .backlog/ da paydo bo'ladi
- [x] #5 Loyihani UI'dan qo'shish va o'chirish mumkin
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Backend: mavjud API yetarli (GET /projects, /board, /tasks/{id}; POST /projects, DELETE /projects/{id}; POST /tasks, /status, /labels). O'zgarish faqat jonli tekshiruvda kamchilik chiqsa.
2. API qatlami: types (Board, TaskItem, TaskDetail, Milestone), useBoard/useTaskDetail (2.5 s polling, loyiha bekloqi xato bo'lsa o'chiq), mutatsiya hook'lari (createTask, setStatus, addLabels, addProject, removeProject) — muvaffaqiyatda projects/board/detail invalidate; xato ApiError → i18n matni.
3. Sof funksiyalar (web/src/board/model.ts) + vitest: statuslar bo'yicha ustunlar (config tartibi, keyin noma'lum statuslar; ordinal, keyin ID), label/milestone filtrlari (label — istalgan tanlangani; milestone — id yoki sarlavha, 'milestonesiz'), label ro'yxati (config + vazifalardagi), loyiha ID slug'i, qatorlarga ajratish.
4. Chap panel: loyiha kartochkasida status hisoblagichlari (config tartibida), bug (ochiq/jami), faol sessiyalar va blocked (KanBot yo'q bo'lsa '—'); '+ Loyiha' formasi (nom, ID avtomatik slug, bekloq papkasi, repolar — ixtiyoriy); o'chirish inline tasdiq bilan (faqat registrdan, fayllar qolishi aytiladi).
5. Markaz: filtr qatori (label chiplari, milestone select, tozalash, ko'rinayotgan/jami), status ustunlari, kartochka (ID, sarlavha, labellar, ijrochi, AC x/y, DoD x/y), kartochkani boshqa ustunga sudrab status o'zgartirish; '+ Vazifa' formasi (sarlavha, tavsif, status, labellar, ijrochi, milestone, AC qatorlari).
6. Detal panel (doska ichida o'ng drawer): sarlavha, status select, labellar + label qo'shish, ijrochi/milestone/priority, tavsif, AC va DoD ro'yxati, plan, notes, yakuniy xulosa, bog'liqliklar va subtask'lar (status bilan, bosilsa o'sha vazifa ochiladi), parent.
7. Barcha yangi matnlar uz lug'atiga; qorong'i zich uslub.
8. Tekshiruv: make check, build; jonli: Agent Hub bekloqi nusxasi (scratch) va demo — hisoblagichlarni backlog task list --json bilan solishtirish, filtrlar, detal, yaratish/status/label natijasi .backlog/ fayllarida, loyiha qo'shish/o'chirish UI'dan. Leveling faqat o'qiladi.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Backend API o'zgarmadi; frontend mavjud endpointlar ustida.
- Label filtri CLI 'backlog task list --labels' kabi AND (tanlangan har bir label bo'lishi kerak), registrsiz; rejadagi 'istalgani' jonli solishtiruvdan keyin o'zgartirildi. Label ro'yxati: config labellari + vazifalardagi labellar.
- Milestone filtri id yoki sarlavha bo'yicha (vazifada ikkalasi ham uchraydi), 'Milestone'siz' varianti bor.
- Status o'zgartirish: kartochkani ustunga sudrash (HTML5 DnD) yoki detal paneldagi select; ikkalasi POST /tasks/{id}/status.
- Modal: native <dialog>.showModal() fokusni 'Yopish' tugmasiga beradi — probel bosilsa dialog yopilardi; fokus formaning birinchi maydoniga o'tkazildi.
- Detal panel doska ustida o'ng drawer (tor ekranda doskani yopadi). Kartochkadagi sessiyalar va sessiya ochish — TASK-10.
- Tekshiruv: make check (pytest 379, vitest 27), make build, eslint/tsc toza. Jonli (Chrome, scratch nusxalar): UI'dan TASK-20 yaratildi (labellar, tavsif, 2 AC) — fayl .backlog/tasks'da; select bilan In Progress, drag bilan Done, 'bug' label qo'shildi — backlog task view tasdiqladi; hisoblagichlar backlog task list --json bilan mos (hubcopy 10/1/9 bug 0/1, demo 0/1/0 bug 1/1); filtrlar CLI -l/-m natijalari bilan mos (client 9, client+bug 1, bug+backend 0, m-0 12, m-1 4, m-2 3); loyiha 'Demo nusxa' UI'dan qo'shildi va o'chirildi — projects.yaml tasdiqladi, bekloq fayllari joyida; konsolda xato yo'q. Leveling faqat o'qildi.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Loyihalar paneli va vazifalar doskasi qo'shildi. Chap panel: status hisoblagichlari, bug ochiq/jami, faol/blocked sessiyalar (KanBot yo'q bo'lsa '—'), '+ Loyiha' formasi (ID nomdan slug) va tasdiqli o'chirish (faqat registrdan). Markaz: label (AND, CLI kabi) va milestone filtrlari, status ustunlari, kartochkada ID/sarlavha/labellar/ijrochi/AC va DoD progressi, sudrab status o'zgartirish, '+ Vazifa' formasi. Detal drawer: status select, label qo'shish, tavsif, AC/DoD, plan, notes, yakuniy xulosa, bog'liqliklar va subtask'lar (bosilsa ochiladi). Backend o'zgarmadi. Tekshiruv: make check (pytest 379, vitest 27 — board/model testlari), build; Chrome'da scratch nusxalarda yaratish/status/label natijalari backlog CLI bilan, hisoblagich va filtrlar backlog task list --json/-l/-m bilan solishtirildi, loyiha qo'shish/o'chirish projects.yaml'da tasdiqlandi.
<!-- SECTION:FINAL_SUMMARY:END -->
