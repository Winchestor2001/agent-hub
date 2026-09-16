---
id: TASK-31
title: 'Kanban: tugagan ustunda yangi vazifalar yuqorida'
status: Done
assignee:
  - '@claude'
created_date: '2026-09-16 06:27'
updated_date: '2026-09-16 06:28'
labels:
  - client
dependencies: []
ordinal: 31000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Doskadagi har bir ustun ordinal (yaratilish tartibi) bo'yicha o'sish yo'nalishida saralanadi. Tugagan (oxirgi) ustunda bu eng eski vazifani tepaga chiqaradi, yangi bajarilganini esa ro'yxat oxiriga tashlaydi — foydalanuvchi oxirgi natijani ko'rish uchun pastga aylantirishga majbur. Terminal ustunda tartib teskari bo'lishi kerak: eng oxirgi (yaqinda yangilangan) vazifa tepada.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Tugagan (config'dagi oxirgi) ustun updated_at bo'yicha kamayish tartibida chiqadi; sana bo'lmasa created_at, keyin ordinal/ID bo'yicha teskari
- [x] #2 Qolgan ustunlar avvalgidek ordinal, keyin ID bo'yicha o'sish tartibida qoladi
- [x] #3 web/src/board/model.test.ts da ikkala tartib uchun test bor va butun test to'plami o'tadi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. model.ts: byOrdinalThenId'ga qo'shimcha byRecencyDesc komparatori (updated_at → created_at → ordinal → ID, teskari).
2. groupByStatus: config'dagi oxirgi status (terminal ustun) uchun byRecencyDesc, qolganlari uchun byOrdinalThenId.
3. model.test.ts: tugagan ustun teskari, boshqa ustunlar o'sish tartibida ekanini tekshiruvchi testlar.
4. npm test (vitest) + tsc.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
groupByStatus endi ustunga qarab komparator tanlaydi: config'dagi oxirgi status uchun byRecencyDesc (updated_at → created_at, ISO satr solishtiruvi; sanasizlar pastda, ular orasida ordinal/ID teskari), qolganlari uchun avvalgi byOrdinalThenId. Noma'lum (config'da yo'q) statuslar tugagan hisoblanmaydi. Tekshiruv: web/ da npm test (12 fayl, 89 test), npm run typecheck, npm run lint — hammasi toza.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Kanban ustunlarining saralashi ustunga bog'landi: tugagan (config'dagi oxirgi) ustun endi yangilanish vaqti bo'yicha kamayish tartibida — oxirgi bajarilgan vazifa tepada; qolgan ustunlar navbat tartibini (ordinal, keyin ID) saqlaydi. web/src/board/model.ts da byRecencyDesc komparatori qo'shildi, groupByStatus terminal ustunni ajratadi. model.test.ts ga tugagan ustun uchun ikki test qo'shildi (sanali va sanasiz holat); npm test, typecheck va lint o'tdi.
<!-- SECTION:FINAL_SUMMARY:END -->
