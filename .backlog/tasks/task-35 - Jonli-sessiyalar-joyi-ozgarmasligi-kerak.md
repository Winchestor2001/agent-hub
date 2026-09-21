---
id: TASK-35
title: Jonli sessiyalar joyi o'zgarmasligi kerak
status: Done
assignee:
  - '@claude'
created_date: '2026-09-21 08:06'
updated_date: '2026-09-21 08:18'
labels:
  - client
dependencies: []
ordinal: 35000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Sessiyalar panelida jonli sessiyalar joyini tez-tez almashtiradi: backend sort_panes ro'yxatni holat (blocked/working/idle) va oxirgi chiqish vaqti bo'yicha saralaydi, agent har safar chiqish bersa yoki holati o'zgarsa qator sakraydi; frontend esa blocked pane'larni alohida «Javob kutmoqda» bo'limiga ko'chiradi. Foydalanuvchi qatorni bosmoqchi bo'lganda u ko'chib ketadi. Tartib barqaror bo'lishi kerak: sessiya joyi faqat qo'shilganda/yopilganda o'zgarsin, holat va chiqish o'zgarishi bilan emas. Shortcut (Alt+Shift+↑/↓) tartibi panel tartibi bilan mos bo'lsin.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Jonli sessiyalar boshlanish vaqti (eskisi tepada), keyin ID bo'yicha barqaror tartiblanadi; holat yoki oxirgi chiqish o'zgarishi joyni o'zgartirmaydi (GET /api/sessions va vazifa detali sessiyalari)
- [x] #2 Panelda blocked pane alohida bo'limga ko'chmaydi: o'z joyida qoladi va rang/belgi bilan ajralib turadi
- [x] #3 Alt+Shift+↑/↓ tartibi panelda ko'rinadigan tartib bilan bir xil
- [x] #4 Backend va frontend uchun testlar barqaror tartibni tekshiradi; pytest, vitest, typecheck, lint va build o'tadi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. backend views.sort_panes: (started_at, id) bo'yicha barqaror tartib, STATE_ORDER olib tashlanadi. 2. frontend: groupLive va blocked bo'limi olib tashlanadi, LiveList bitta ro'yxat; blocked qator .session-blocked bilan ajratiladi. 3. navigationOrder backend tartibini saqlaydi (blocked birinchi qoidasi olib tashlanadi). 4. Testlar: test_sessions, test_tasks, navigation.test, model.test. 5. Tekshiruv: pytest, ruff, mypy, vitest, tsc, eslint, build.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Backend: views.sort_panes endi (started_at, id) bo'yicha barqaror saralaydi (started_at yo'qlar oxirda); STATE_ORDER va oxirgi chiqish bo'yicha saralash olib tashlandi. Bu GET /api/sessions va vazifa detali sessiyalariga ham ta'sir qiladi. Frontend: groupLive va «Javob kutmoqda» bo'limi (sessions.blocked kalitlari, .section-blocked CSS, Section.className) olib tashlandi, blocked qator o'z joyida .session-blocked bilan ajratiladi. navigationOrder olib tashlandi — Alt+Shift+↑/↓ endi panel (backend) tartibida o'tadi. Testlar: test_live_order_ignores_state_and_output, test_live_order_ties_by_id_and_unknown_start_last, test_list_sessions yangilandi, model.test.ts (tartib saqlanishi). pytest 559, ruff/mypy, vitest 100, tsc, eslint, build o'tdi. #2 (blocked qatorning vizual ko'rinishi) brauzerda ko'zdan kechirilmagan — make install dan keyin foydalanuvchi tekshiradi.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Jonli sessiyalar barqaror tartibda (boshlanish vaqti, keyin ID): holat yoki chiqish o'zgarsa qator joyidan ko'chmaydi. Backend sort_panes va frontend blocked bo'limi olib tashlandi, blocked qator o'z joyida qizil fon bilan ajraladi, Alt+Shift+↑/↓ panel tartibida o'tadi. Foydalanuvchi make install dan keyin tasdiqladi. Testlar: pytest 559, vitest 100, typecheck, lint, build o'tdi.
<!-- SECTION:FINAL_SUMMARY:END -->
