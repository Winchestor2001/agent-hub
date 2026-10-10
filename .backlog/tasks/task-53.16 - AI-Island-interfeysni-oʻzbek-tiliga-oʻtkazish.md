---
id: TASK-53.16
title: 'AI Island: interfeysni oʻzbek tiliga oʻtkazish'
status: Done
assignee:
  - '@claude'
created_date: '2026-10-10 15:13'
updated_date: '2026-10-10 20:29'
labels:
  - ai-island
  - ux
  - i18n
dependencies:
  - TASK-53.4
  - TASK-53.5
  - TASK-53.8
  - TASK-53.9
  - TASK-53.12
  - TASK-53.13
  - TASK-53.14
references:
  - macos/AIIslandApp/Sources/AIIslandApp/main.swift
  - macos/AIIslandApp/Sources/AIIslandApp/ClaudeAccountsWindow.swift
parent_task_id: TASK-53
priority: medium
type: enhancement
ordinal: 76000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
AI Island ning barcha matnlari (island, popover, Settings, editor, Accounts oynasi, alertlar, menyular) inglizcha, loyiha qoidasiga koʻra esa MVP UI faqat oʻzbek tilida (lotin) boʻlishi kerak; rus tili keyinroq (M3). Matnlarni oʻzgartiradigan boshqa subtasklardan keyin bajariladi, ikki marta tarjima qilmaslik uchun.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Foydalanuvchiga koʻrinadigan barcha satrlar oʻzbek tilida (lotin, toʻgʻri oʻ/gʻ belgilari bilan); CLI nomlari va fayl yoʻllari oʻzgarmaydi
- [x] #2 Satrlar bitta joyda (Localizable.strings/String Catalog yoki yagona lugʻat) saqlanadi, keyinchalik rus tili qoʻshish mumkin
- [x] #3 Oʻzbekcha uzunroq matnlar island, popover va kartalarda kesilmaydi (skrinshot bilan tasdiqlangan)
- [x] #4 Regressiya testlaridagi matn tekshiruvlari yangilanadi va barchasi oʻtadi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Sources/ClaudeSessions/Localization.swift: inglizcha manba matn kalit boʻlgan yagona oʻzbekcha lugʻat va tr() funksiyasi (kalit topilmasa inglizcha qaytadi; keyin ruscha lugʻat qoʻshish mumkin).
2. main.swift va ClaudeAccountsWindow.swift dagi koʻrinadigan matnlar, menyular, tooltip va VoiceOver yozuvlarini tr() orqali chiqarish. Model kalitlari, identifikatorlar, zaxira papka nomlari va DB qiymatlari inglizcha qoladi, faqat koʻrsatishda tarjima qilinadi.
3. Kutubxona: SessionError, sintaksis xatolari, ResetCountdown, readiness va tarix yozuvlarini koʻrsatishda tarjima qilish; sanalar uz_Latn formatida.
4. Unit test: manbadagi har bir tr("...") uchun oʻzbekcha tarjima borligi, ortiqcha kalit yoʻqligi va oʻ/gʻ da ʻ ishlatilishi tekshiriladi.
5. Regressiyalarni yangi matnlarga moslash, hammasini ishga tushirish, shasum tekshiruvi.
6. Release ilovada orol, popover, kartalar, Settings, muharrir va Accounts skrinshotlari bilan kesilish yoʻqligini tekshirish.
Doiradan tashqari: terminaldagi cca CLI.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Lugʻat: Sources/ClaudeSessions/Localization.swift (kalit — inglizcha manba matn, tr() koʻrsatishda tarjima qiladi, kalit topilmasa inglizcha). Rus tilini qoʻshish: Language ga case, alohida lugʻat va Language.current. cca CLI doiradan tashqari, inglizcha qoldi.
LocalizationTests: har bir tr() uchun tarjima borligi, ortiqcha kalit yoʻqligi, placeholderlar soni mosligi, SessionError/readiness/tarix qiymatlari tarjimasi va oʻ/gʻ da ʻ, tutuqda ʼ ishlatilishi.
Undo/Redo: AppKit standart undo: elementlarini inglizcha (Undo Typing) qayta nomlardi; oʻz amallari va validateMenuItem bilan tarjima saqlanadi. Fayl muharririda undo tarixi yoʻq (NSTextView allowsUndo sukut boʻyicha false, oldin ham shunday edi); CLAUDE_SESSIONS.md shunga moslandi va til boʻlimi qoʻshildi.
Popover: 7D yozuvi oʻzbekchada sigʻmagani uchun 2 qatorga oʻraladi, qolgan vaqt boʻlinmas boʻshliq bilan; usage regressiyasida tekshiriladi.
Tekshiruv: swift test 60/60, regressiyalar settings 103, usage 52, accounts 35 — barchasi PASS; ~/.claude/settings.json va ~/.codex/config.toml shasum OK. Release skrinshotlari: orol, popover, Settings (Umumiy, Codex, Claude, Akkauntlar), muharrir, Accounts oynasi — kesilish yoʻq.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
AI Island interfeysi oʻzbek tiliga (lotin) oʻtkazildi: barcha koʻrinadigan matnlar, menyular, tooltip va VoiceOver yozuvlari yagona Localization.swift lugʻatidan tr() orqali chiqadi; model qiymatlari va CLI inglizcha qoldi, rus tilini keyin qoʻshish mumkin. Undo/Redo menyusi tarjimasi saqlanadi, popover yozuvi uzun boʻlsa 2 qatorga oʻraladi. swift test 60/60, uchta regressiya (103/52/35) PASS, config shasum OK, release skrinshotlarida kesilish yoʻq.
<!-- SECTION:FINAL_SUMMARY:END -->
