---
id: TASK-53.1
title: 'Editor: saqlanmagan tahrirlarni yoʻqotmaslik'
status: Done
assignee:
  - '@claude'
created_date: '2026-10-10 15:13'
updated_date: '2026-10-10 16:30'
labels:
  - ai-island
  - ux
dependencies: []
references:
  - macos/AIIslandApp/Sources/AIIslandApp/main.swift
parent_task_id: TASK-53
priority: high
type: bug
ordinal: 61000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Konfiguratsiya editorida boshqa fayl tanlanganda yoki oyna yopilganda `loadConfigurationFile` editor matnini hech narsa soʻramay almashtiradi — foydalanuvchi tahriri jimgina yoʻqoladi. Qidiruv qoralamani saqlaydi, fayl tanlash esa saqlamaydi, bu nomuvofiq va xavfli. Saqlash uchun klaviatura yorligʻi ham yoʻq.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Tahrir qilingan, saqlanmagan fayl UIda belgilanadi (masalan, sarlavhada nuqta yoki "Edited" yozuvi, oyna documentEdited holati)
- [x] #2 Saqlanmagan oʻzgarish bor paytda boshqa fayl tanlash, kategoriya almashtirish yoki oynani yopish Save / Discard / Cancel tanlovini beradi; Cancel tanlov va matnni oʻzgarishsiz qoldiradi
- [x] #3 ⌘S saqlash oqimini (review + backup) ishga tushiradi
- [x] #4 Native regressiya: tahrir → boshqa fayl tanlash → Cancel holatida qoralama saqlanib qolishi tekshiriladi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Saqlangan matn (configurationSavedContent) yuklashda va saqlashda yangilanadi; dirty = faol fayl bor va editor matni undan farq qiladi.
2. Belgi: editor delegate textDidChange → oyna isDocumentEdited (yopish tugmasidagi nuqta) va status satrida "Edited · unsaved changes · ⌘S to review and save".
3. resolveUnsavedConfigurationChanges(): Save (mavjud review + backup oqimi) / Discard (saqlangan matnga qaytaradi) / Cancel (false). Dialog test uchun almashtiriladigan closure orqali.
4. Ulanish nuqtalari: tableView(_:shouldSelectRow:) (boshqa fayl), openConfigurationCategory (kategoriya), createConfigurationFile, windowShouldClose (oyna delegate), applicationShouldTerminate (oyna yashirin, qoralama bor boʻlsa).
5. ⌘S: Review & Save tugmasiga keyEquivalent; saveConfigurationFile Bool qaytaradigan funksiyaga ajratiladi.
6. Settings regressiyasi: insertText bilan tahrir → isDocumentEdited va status; Cancel bilan boshqa fayl/kategoriya/yopish → qoralama va tanlov saqlanadi; ⌘S review chaqiradi (rad etiladi, fayl yozilmaydi); Discard → asl matn. Foydalanuvchi fayllari yozilmaydi.
7. swift test, settings/usage/accounts regressiyalari, release build.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Dirty holat editor matnini oxirgi yuklangan/saqlangan matn bilan solishtirib aniqlanadi (configurationSavedContent), shuning uchun dasturiy oʻzgarishlar ham hisobga olinadi. Fayl almashtirish tableView(_:shouldSelectRow:) da ushlanadi: Cancel tanlovni oʻzgartirmaydi, oʻsha qatorni qayta bosish soʻramaydi. ⌘Q (Close Settings) oynalar ochiq boʻlsa avvalgidek ularni yashiradi va qoralama xotirada qoladi; oynalar yashirin, qoralama esa bor boʻlsa, Quit ham soʻraydi. Yangi fayl yaratish ham avval soʻraydi. Dialoglar regressiya uchun closure orqali almashtiriladi. Eslatma: yangi enum @MainActor atributini AppDelegate'dan ajratib qoʻygan edi — tuzatildi. Tekshiruv: settings regressiyasi 104 PASS (3 kategoriyada yangi 'unsaved edits' checki: belgi, fayl/kategoriya/yopishda Cancel qoralamani saqlaydi, ⌘S review chaqiradi, rad etilgan review faylni yozmaydi, Discard asl matnni qaytaradi); usage 22/22, accounts 22 PASS, swift test 0 xato, release build.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Konfiguratsiya editori endi saqlanmagan tahrirlarni yoʻqotmaydi. Tahrir qilingan fayl yopish tugmasidagi nuqta (isDocumentEdited) va "Edited · unsaved changes · ⌘S to review and save" statusi bilan belgilanadi. Boshqa fayl yoki kategoriya tanlash, yangi fayl yaratish, oynani yopish va (oyna yashirin boʻlsa) Quit qilishdan oldin Save… / Discard / Cancel soʻraladi. Cancel tanlov va matnni oʻzgarishsiz qoldiradi. ⌘S mavjud review + backup oqimini ishga tushiradi. Tekshiruv: settings regressiyasi (104 PASS, 3 ta yangi check), usage va accounts regressiyalari, swift test, release build.
<!-- SECTION:FINAL_SUMMARY:END -->
