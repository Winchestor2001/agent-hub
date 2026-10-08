---
id: TASK-51
title: >-
  AI Island va cca: barcha Claude akkauntlari holati, akkaunt nomli statusline
  va yangi ranglar
status: Done
assignee:
  - '@claude'
created_date: '2026-10-08 12:36'
updated_date: '2026-10-08 12:41'
labels:
  - ai-island
  - accounts
  - cli
dependencies: []
ordinal: 58000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Foydalanuvchi qaysi Claude akkauntidan foydalanayotganini bilolmayapti: cca statusline'i faqat oddiy matn, AI Island'dagi Claude kartasi esa bitta usage'ni ko'rsatadi va u qaysi akkauntniki ekani noma'lum. Ranglar: Claude Codex'ning hozirgi (to'q sariq) rangini oladi, Codex esa ChatGPT kabi oq bo'ladi.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 cca orqali ochilgan Claude statusline'ida akkaunt nomi rangli belgi bilan ajralib turadi, shuningdek model, papka, git branch, kontekst qoldig'i, 5h va 7d foizlari va reset vaqtlari ko'rsatiladi
- [x] #2 Akkaunt usage'i 5h va 7d oynalari bo'yicha alohida saqlanadi; limit tekshiruvi eng katta foizdan foydalanishda davom etadi
- [x] #3 AI Island popover'idagi Claude kartasida Default (oddiy claude, ~/.claude) va har bir akkaunt alohida qatorda: nom, holat va obuna, 5H/7D foiz chiziqlari va reset; oxirgi ishlatilgani 'NOW' belgisi bilan
- [x] #4 Island'dagi Claude halqasi oxirgi ishlatilgan manbaning foizini ko'rsatadi; tooltip'da barcha manbalar ro'yxati bor
- [x] #5 Claude rangi to'q sariq (avvalgi Codex rangi), Codex rangi oq; ikkala joyda (island va popover) bir xil
- [x] #6 Testlar va native regressiyalar yangilanib o'tadi, release build, app qayta ochiladi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Store.usageWindows(account): har oyna (five_hour/seven_day) bo'yicha oxirgi snapshot, reset o'tgan oyna tashlanadi; usage() = ulardan eng kattasi. recordUsage har oynani alohida yozadi.
2. AccountCLI.statusLine: ANSI rangli akkaunt belgisi (akkaunt tartibiga ko'ra rang), model, papka (~), git branch, kontekst %, 5h/7d foiz + reset (statusline.sh uslubida).
3. main.swift: accentColor yagona manba — Claude to'q sariq, Codex oq; providerRow ham shuni ishlatadi.
4. ClaudeAccountsController: claudeSources (Default + akkauntlar: nom, holat, oynalar, oxirgi yangilanish). Popover Claude kartasi har manba uchun qator va 5H/7D chiziqlari, NOW belgisi; karta va popover balandligi dinamik. Halqa = eng so'nggi yangilangan manba; tooltip barcha manbalar.
5. Regressiyalar (accounts/usage) va XCTest yangilanadi; swift test, release build, app qayta ochiladi.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Tekshiruv: accounts regression 20/20 (yangi: Claude kartasida Default + har akkaunt, NOW belgisi, Codex oq / Claude to'q sariq halqa), usage regression 14/14, swift test 28/28 (AccountCLITests statusline: rangli belgi, papka, kontekst, 5h/7d, usageWindows). Popover snapshot ko'zdan kechirildi. Release binary bilan haqiqiy 2-akkaunt uchun statusline chiqishi tekshirildi (rate_limits'siz kirish bazaga yozmaydi).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
cca statusline endi rangli akkaunt belgisi, model, papka, branch, kontekst va 5h/7d limitlarini ko'rsatadi; usage oynalar bo'yicha alohida saqlanadi. AI Island Claude kartasi Default (~/.claude) va har bir akkauntni alohida ko'rsatadi, hozir ishlatilayotganini NOW bilan belgilaydi; halqa shu manbaning foizini ko'rsatadi. Claude to'q sariq, Codex oq. Tekshiruv: regressiyalar 20/20 va 14/14, swift test 28/28, release build.
<!-- SECTION:FINAL_SUMMARY:END -->
