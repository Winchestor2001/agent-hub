---
id: TASK-54
title: >-
  AI Island: Update tugmasi Homebrew orqali oʻrnatilgan Claude Code'ni
  yangilamaydi
status: Done
assignee:
  - '@claude'
created_date: '2026-10-11 07:25'
updated_date: '2026-10-11 07:29'
labels:
  - ai-island
dependencies: []
references:
  - macos/AIIslandApp/Sources/AIIslandApp/main.swift
priority: high
type: bug
ordinal: 77000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Popover dagi Update tugmasi Terminal skriptini ochadi, u har bir CLI uchun `<cli> update` ni chaqiradi. Claude Code Homebrew cask (`claude-code@latest`) orqali oʻrnatilgan boʻlsa, `claude update` oʻzini yangilamaydi — faqat "Claude is managed by Homebrew… To update, run: brew upgrade claude-code@latest" deb yozadi (2.1.296 binaridagi update mantiqi bilan tasdiqlangan). Natijada foydalanuvchi tugmani bosgandan keyin ham `brew upgrade claude-code@latest` yana yangi versiya oʻrnatadi. Codex (`codex` cask) oʻzi `brew upgrade --cask codex` ni chaqiradi.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Homebrew cask dan oʻrnatilgan CLI (Caskroom ichidagi realpath) uchun skript `brew upgrade --cask <cask>` ni ishga tushiradi; cask nomi realpath dan olinadi (claude-code@latest, claude-code, codex)
- [x] #2 Homebrew dan tashqari oʻrnatilgan yoki brew topilmagan CLI uchun avvalgidek `<cli> update` chaqiriladi
- [x] #3 Yangi matnlar oʻzbekcha tarjimaga ega; accounts regressiyasi yangi skriptni tekshiradi va swift test oʻtadi
- [x] #4 Haqiqiy tizimda skript Homebrew yoʻlini tanlashi va cask nomlarini toʻgʻri aniqlashi tekshirilgan
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. updateScript ga cask aniqlovchi funksiya: command -v + realpath, */Caskroom/<cask>/* boʻlsa cask nomi.
2. Cask topilsa va brew bor boʻlsa brew upgrade --cask <cask>, aks holda <cli> update.
3. Yangi "via Homebrew" matni uchun Localization.swift ga uz tarjima.
4. Accounts regressiyasidagi Update tekshiruvini yangilash.
5. Skriptni sinov PATH bilan (soxta Caskroom va soxta brew) va haqiqiy tizimda quruq rejimda tekshirish; swift test, regressiyalar, release build.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Sabab: claude 2.1.296 da update buyrugʻi installationType=package-manager va homebrew boʻlsa faqat 'To update, run: brew upgrade <cask>' yozadi, oʻzi yangilamaydi. Codex esa BrewUpgrade yoʻli bilan brew upgrade --cask codex ni oʻzi chaqiradi.
Tekshiruv: ilova yozgan skript soxta PATH bilan sinaldi — (A) ikkala CLI cask: brew upgrade --cask claude-code@latest va codex chaqirildi; (B) claude cask emas: claude update, codex brew; (C) brew yoʻq: ikkalasi ham <cli> update. Haqiqiy tizimda cask_of: claude -> claude-code@latest, codex -> codex, brew /opt/homebrew/bin/brew (yangilash ishga tushirilmadi, claude allaqachon 2.1.296). swift test 60/60; regressiyalar accounts 36 (yangi Homebrew tekshiruvi), usage 52, settings 103 — 0 FAIL. Release build qayta ochildi.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Update tugmasi skripti CLI Homebrew cask dan oʻrnatilganini realpath (*/Caskroom/<cask>/*) orqali aniqlaydi va brew upgrade --cask <cask> ni ishga tushiradi; boshqa oʻrnatishlarda avvalgidek <cli> update. Sabab: claude update Homebrew ostida faqat brew buyrugʻini yozib qoʻyadi. 'Homebrew orqali: …' matni uchun oʻzbekcha tarjima. Soxta brew/Caskroom bilan uch holat, haqiqiy tizimda cask aniqlash, swift test 60/60 va uchala regressiya (accounts 36) bilan tekshirildi.
<!-- SECTION:FINAL_SUMMARY:END -->
