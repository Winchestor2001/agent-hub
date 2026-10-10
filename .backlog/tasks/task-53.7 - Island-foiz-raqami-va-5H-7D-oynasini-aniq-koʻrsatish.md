---
id: TASK-53.7
title: 'Island: foiz raqami va 5H/7D oynasini aniq koʻrsatish'
status: Done
assignee:
  - '@claude'
created_date: '2026-10-10 15:13'
updated_date: '2026-10-10 17:36'
labels:
  - ai-island
  - ux
dependencies: []
references:
  - macos/AIIslandApp/Sources/AIIslandApp/main.swift
parent_task_id: TASK-53
priority: medium
type: enhancement
ordinal: 67000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Halqa ichida faqat logo bor, raqam yoʻq; halqa 5H va 7D dan kattasini (`maxPercent`) koʻrsatadi, lekin qaysi oyna ekanini foydalanuvchi bilmaydi. Halqa ostidagi chiziq ayni shu qiymatni takrorlaydi va yangi maʼlumot bermaydi.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Har bir provayder katakchasida joriy foiz raqam bilan koʻrinadi (oʻqiladigan oʻlchamda)
- [x] #2 Halqa va chiziq ikki xil maʼlumot beradi (masalan, halqa = 5H, chiziq = 7D) yoki takroriy element olib tashlanadi; qaysi oyna ekani tooltipda yoziladi
- [x] #3 Island kengligi 58px dan oshmaydi yoki oʻzgarish asoslanib, skrinshot bilan tasdiqlanadi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. IslandUsage.known endi ikki oynani olib yuradi (5H, 7D). Codex: primary/secondary. Claude: joriy manba, aks holda faol akkaunt qatori, aks holda Default (~/.claude) manbasi.
2. Katak: halqa = 5H (logo ichida qoladi), halqa ostida 5H foizi raqam bilan (10pt, monospaced, daraja rangida), chiziq = 7D. Har biri UsageLevel qoidasi boʻyicha boʻyaladi; oyna nomaʼlum boʻlsa halqa punktir, raqam '—', chiziq boʻsh.
3. '!' belgisi va pulsatsiya istalgan oyna ≥90% boʻlsa chiqadi; belgi har doim qizil, shuning uchun 5H oddiy, 7D kritik boʻlganda ham koʻrinadi.
4. Tooltip: 'Ring: 5H …% used · Bar: 7D …% used'.
5. Kenglik 58px boʻlib qoladi; katak balandligi 48 → 51, 126px island ichiga sigʻadi, faqat Codex koʻrinadigan holatda balandlik 58 → 66.
6. Usage regressiyasi: raqam, 5H/7D ajratilishi, aralash holat (5H 10%, 7D 95%), tooltip, island oʻlchami; skrinshot. swift test, uchala regressiya, release build.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
IslandUsage.known endi IslandWindows(fiveHour, sevenDay) olib yuradi. Codex: primary/secondary. Claude (claudeIslandWindows): joriy manba, keyin faol akkaunt (yangi ClaudeAccountsController.activeAccountName), keyin Default. Oldingi maxPercent aralashmasi olib tashlandi.
Katak: halqa = 5H, logo ichida qoladi; halqa ostida 5H raqami (10pt monospaced semibold, daraja rangida; loading '…', nomaʼlum '—'); chiziq = 7D, oʻz daraja rangida. 5H nomaʼlum, 7D maʼlum boʻlsa: punktir halqa, '—', 7D chiziq.
'!' belgisi istalgan oyna ≥90% boʻlsa chiqadi va doim qizil, shuning uchun oddiy 5H halqada ham koʻrinadi.
Tooltip: 'Codex · Ring: 5H 10% used · Bar: 7D 95% used'; Claude'da bu satr akkaunt xulosasidan oldin turadi.
Kenglik 58px boʻlib qoldi. Katak balandligi 48 → 51, 126px ichiga sigʻadi. Faqat Codex koʻrinadigan holatda balandlik 58 → 66.
Tekshiruv: swift test 52/52. Usage regressiyasi 29 PASS: raqam (…, —, 0%, 50/80/95%), aralash 5H 10% / 7D 95% holati, tooltip matni, 58pt kenglik va 100% raqamning sigʻishi. Settings 104, accounts 23 PASS. usage.island.png va haqiqiy island skrinshoti (58×126, Codex 0%, Claude 24%) koʻrib chiqildi.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Island katagi endi ikki oynani ajratib koʻrsatadi: halqa va uning ostidagi raqam 5H oynasi, chiziq 7D oynasi. Har biri UsageLevel rangida. Tooltip qaysi element qaysi oyna ekanini yozadi. Istalgan oyna ≥90% boʻlsa qizil '!' belgisi chiqadi. Island kengligi 58px boʻlib qoldi. Tekshirildi: swift test 52/52, regressiyalar usage 29, settings 104, accounts 23 PASS, regressiya rasmi va haqiqiy island skrinshoti koʻrib chiqildi.
<!-- SECTION:FINAL_SUMMARY:END -->
