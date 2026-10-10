---
id: TASK-53.3
title: 'Editor: JSON va TOML fayllarni saqlashdan oldin tekshirish'
status: Done
assignee:
  - '@claude'
created_date: '2026-10-10 15:13'
updated_date: '2026-10-10 17:00'
labels:
  - ai-island
  - ux
dependencies: []
references:
  - macos/AIIslandApp/Sources/AIIslandApp/main.swift
parent_task_id: TASK-53
priority: high
type: enhancement
ordinal: 63000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`settings.json`, `settings.local.json`, `~/.claude.json` va `config.toml` sintaksis xatosi bilan saqlanishi mumkin — shundan keyin Claude Code yoki Codex ishga tushmay qoladi. Backup bor, lekin xatoning oldini olish undan yaxshiroq.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 .json fayllar saqlashdan oldin parse qilinadi; xato boʻlsa qator/ustun bilan aniq xabar chiqadi va fayl yozilmaydi
- [x] #2 .toml fayllar uchun kamida asosiy sintaksis tekshiruvi bor (yoki xato aniqlansa ogohlantirib, foydalanuvchi ongli ravishda "baribir saqlash"ni tanlashi mumkin)
- [x] #3 Toʻgʻri fayllar oldingidek review + backup oqimi bilan saqlanadi
- [x] #4 Testlar: yaroqli va yaroqsiz JSON/TOML namunalari
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ClaudeSessions'da ConfigurationSyntax: qatʼiy JSON parser va TOML tuzilma tekshiruvi (qator/ustun, UTF-16 offset).
2. Unit testlar: toʻgʻri va notoʻgʻri JSON/TOML namunalari; haqiqiy fayllarda soxta xato yoʻqligini tekshirish.
3. saveActiveConfigurationFile: review'dan oldin validatsiya. JSON xatosi boʻlsa fayl yozilmaydi; TOML xatosida ogohlantirish va ongli 'Save Anyway' tanlovi. Kursor xato joyiga qoʻyiladi, status satrida qator/ustun koʻrsatiladi.
4. Dialog injectable closure (presentConfigurationSyntaxProblem), regressiya uni boshqaradi.
5. Settings regressiyasi: notoʻgʻri JSON ⌘S'da sintaksis xatosiga uriladi va yozilmaydi; toʻgʻri qoralama review'ga oʻtadi.
6. swift test, uchala regressiya, release build.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ConfigurationSyntax (ClaudeSessions): qatʼiy JSON parser (trailing comma, izoh, qoʻshtirnoqsiz kalit, leading zero, qiymatdan keyingi matn) va TOML tuzilma tekshiruvi (kalit/jadval, [[array]], satr turlari, son/sana, inline table, takroriy kalit/jadval). Xato qator, ustun va UTF-16 offset bilan qaytadi.
Saqlash: validatsiya review'dan oldin ishlaydi. Kursor xato joyiga qoʻyiladi, status 'Syntax error · line X, column Y: …'. JSON xatosi faqat OK tugmasi bilan bloklanadi va fayl yozilmaydi. TOML xatosi ogohlantiradi ('Keep Editing' standart, 'Save Anyway' ongli tanlov), lekin baribir review + backup'dan oʻtadi.
Tekshiruv: swift test 50/50 (ConfigurationSyntaxTests 13). Soxta xato yoʻq: 300 ta haqiqiy TOML va Python toʻgʻri deb topgan 389 ta JSON fayl validatordan oʻtdi. Settings regressiyasi 104 PASS: Claude::Settings'da notoʻgʻri JSON 34-qatorda bloklandi, review'ga yetmadi, fayl yozilmadi; toʻgʻri JSON review'ga yetdi. Usage 22 PASS, accounts 22 PASS. ~/.claude/settings.json va ~/.codex/config.toml shasum oʻzgarmadi. Regressiyada koʻp faylli TOML kategoriyasi yoʻq, shuning uchun TOML 'Save Anyway' UI yoʻli unit testlar va JSON bilan umumiy kod orqali tasdiqlangan.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
AI Island editori .json va .toml fayllarni saqlashdan oldin tekshiradi. Notoʻgʻri JSON qator/ustun bilan xabar beradi va yozilmaydi. TOML xatosi ogohlantiradi; 'Save Anyway' ongli tanlov boʻlib, baribir review + backup'dan oʻtadi. Kursor xato joyiga oʻtadi. Tekshirildi: swift test 50/50, settings/usage/accounts regressiyalari 104/22/22 PASS (notoʻgʻri JSON bloklandi, fayl yozilmadi), real JSON/TOML fayllarda soxta xato yoʻq.
<!-- SECTION:FINAL_SUMMARY:END -->
