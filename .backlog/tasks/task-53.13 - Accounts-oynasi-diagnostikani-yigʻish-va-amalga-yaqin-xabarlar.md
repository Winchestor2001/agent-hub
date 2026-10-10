---
id: TASK-53.13
title: 'Accounts oynasi: diagnostikani yigʻish va amalga yaqin xabarlar'
status: Done
assignee:
  - '@claude'
created_date: '2026-10-10 15:13'
updated_date: '2026-10-10 19:29'
labels:
  - ai-island
  - ux
dependencies: []
references:
  - macos/AIIslandApp/Sources/AIIslandApp/ClaudeAccountsWindow.swift
parent_task_id: TASK-53
priority: low
type: enhancement
ordinal: 73000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Claude Accounts & Sessions oynasida "Handoff history" va "Developer diagnostics" (CLAUDE_CONFIG_DIR, session ID, PID va h.k.) har doim ochiq turadi va 220px joy egallaydi — bu oddiy foydalanuvchi uchun ichki maʼlumot. Xato va holat xabarlari bitta umumiy qatorda, bosilgan tugmadan uzoqda chiqadi.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Diagnostika va tarix yigʻiladigan (disclosure) boʻlimda, standart holatda yopiq; holat oynalar orasida eslab qolinadi
- [x] #2 Amal natijasi/xatosi tegishli akkaunt yoki sessiya kartasida (yoki uning yonida) koʻrinadi
- [x] #3 Accounts regressiyasi (history va diagnostics mavjudligi) yangilanadi va oʻtadi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. History va diagnostika panellarini "History & diagnostics" disclosure ostiga yigʻish: standart yopiq, holat UserDefaults'da (regressiyada vaqtinchalik suite), yopiq paytda SQLite soʻrovlari bajarilmaydi.
2. Amal natijasi va xatosi uchun notice: maqsad akkaunt yoki sessiya kartasining ichida, tugmalar ostida koʻrinadi; xatoda ogohlantirish belgisi va qizil matn. Maqsadsiz xabarlar (akkaunt oʻchirildi, yangi sessiya) umumiy qatorda qoladi.
3. Accounts regressiyasi: yopiq standart holat, ochilganda history/diagnostika, holat yangi oynada eslab qolinishi, Check natijasi kartada chiqishi tekshiriladi.
4. swift test, uchala regressiya, shasum va release skrinshot.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
History va diagnostika "History & diagnostics" disclosure ostiga yigʻildi: standart yopiq, sarlavhani bosib ham ochiladi, holat UserDefaults'da (ai-island.accounts-details-expanded.v1). Yopiq paytda SQLite soʻrovlari bajarilmaydi, ochilganda panelga scroll qilinadi. Regressiya DetailsPreference orqali holatni xotirada saqlaydi, preference fayl yozmaydi (UserDefaults suite plist qoldirgani uchun shu yoʻl tanlandi).
Amal natijasi notice sifatida tegishli akkaunt yoki sessiya kartasi ichida tugmalar ostida chiqadi; xatoda qizil matn va ogohlantirish belgisi, VoiceOver uchun announcement. Maqsadsiz xabarlar (akkaunt oʻchirildi, yangi sessiya, saqlash xatosi) umumiy qatorda qoladi; yangi natija avvalgisini almashtiradi. Refresh xatosi qayta render qilmaydi, sikl boʻlmaydi.
Accounts regressiyasi 30 dan 35 ga: yopiq standart holat, ochilganda history/diagnostika, yangi oynada holat eslab qolinishi, yopish, kartadagi muvaffaqiyat va xato notice. swift test 54, settings 102, usage 51, accounts 35 PASS; config shasum oʻzgarmagan. Release ilovada yopiq va ochiq holat skrinshotda tekshirildi.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Accounts oynasida history va diagnostika standart yopiq disclosure ostiga oʻtdi va holati eslab qolinadi. Amal natijalari va xatolar endi tegishli akkaunt yoki sessiya kartasida koʻrinadi. Regressiya yangilandi, barcha tekshiruvlar oʻtdi.
<!-- SECTION:FINAL_SUMMARY:END -->
