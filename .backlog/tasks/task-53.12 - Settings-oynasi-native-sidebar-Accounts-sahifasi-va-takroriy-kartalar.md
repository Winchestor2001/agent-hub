---
id: TASK-53.12
title: 'Settings oynasi: native sidebar, Accounts sahifasi va takroriy kartalar'
status: Done
assignee:
  - '@claude'
created_date: '2026-10-10 15:13'
updated_date: '2026-10-10 19:16'
labels:
  - ai-island
  - ux
dependencies: []
references:
  - macos/AIIslandApp/Sources/AIIslandApp/main.swift
parent_task_id: TASK-53
priority: low
type: enhancement
ordinal: 72000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Settings sidebari `texturedRounded` tugmalardan iborat, tanlangan holat faqat rang bilan bildiriladi — macOS uchun native koʻrinmaydi. "Accounts" sahifasida faqat boshqa oynani ochadigan bitta tugma bor (ortiqcha qadam). Codex da "Settings" va "MCP" kartalari bir xil `config.toml` ni ochadi. Sidebar pastidagi "Every future edit will be backed up..." matni ham gʻalati yozilgan.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Sidebar source list uslubida (NSOutlineView/NSTableView .sourceList yoki ekvivalent), tanlangan qator native highlight bilan
- [x] #2 Accounts sahifasi akkauntlar holatini (nom, holat, usage) shu yerda koʻrsatadi yoki sidebar elementi toʻgʻridan-toʻgʻri Accounts oynasini ochadi
- [x] #3 Codex da bir faylga ikki karta qolmaydi (birlashtiriladi yoki MCP kartasi faqat MCP boʻlimiga sakraydi)
- [x] #4 Backup haqidagi matn aniq va toʻgʻri
- [x] #5 Settings regressiyasi yangilanadi va oʻtadi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Sidebar: tugmalar oʻrniga NSTableView .sourceList (alohida SettingsSidebarController data source/delegate), har qatorda SF Symbol va nom, tanlov native highlight. selectedSettingsArea dasturdan oʻzgarsa (Overview kartasi, editor) sidebar tanlovi ham sinxronlanadi.
2. Accounts sahifasi: claudeSources asosida har akkaunt qatori (nom, holat · tarif, 5H/7D usage yoki Usage unknown, eskirganda last known) va pastda Manage Accounts & Sessions… tugmasi.
3. Codex: alohida MCP kartasi olib tashlanadi, Settings kartasi config.toml · global behavior and MCP servers deb nomlanadi.
4. Backup matni haqiqiy xatti-harakatga mos: saqlash yoki oʻchirishdan oldin vaqt belgili nusxa ~/Library/Application Support/AI Island/Backups ga yoziladi.
5. Settings regressiyasi: source list, sidebar tanlovi sahifani almashtirishi va sinxronlanishi, Accounts qatorlari, Codex da config.toml ga bitta karta, backup matni.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Sidebar endi NSTableView source list (SettingsSidebarController): tizim tanlash rangi, SF Symbol ikonlar, AX nomi "Settings sections". Accounts sahifasida har bir Claude akkaunti uchun qator: nom, holat · tarif va 5H/7D foiz (eskirgan boʻlsa "last known"), pastda "Manage Accounts & Sessions…". Codex'dagi alohida MCP kartasi olib tashlandi, "Settings & MCP" bitta config.toml kartasi. Zaxira matni haqiqatga moslandi: Backups papkasiga nusxa saqlash. Settings regression 104 dan 102 ga tushdi (takroriy MCP kartasi tekshiruvlari ketdi, yangi sidebar/Accounts/kartalar tekshiruvlari qoʻshildi). swift test 54, settings 102, usage 51, accounts 30 PASS; config fayllar shasum oʻzgarmagan. Release ilovada skrinshot bilan tekshirildi.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Settings oynasi native source list sidebar oldi, Accounts sahifasi akkaunt nomi, holati va limitlarini koʻrsatadi, Codex'da bitta config.toml uchun bitta karta qoldi, zaxira matni aniqlashtirildi. Barcha testlar va regressionlar oʻtdi.
<!-- SECTION:FINAL_SUMMARY:END -->
