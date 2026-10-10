---
id: TASK-53.9
title: 'Popover: maʼlumot shovqinini kamaytirish va qayta tiklanishgacha qolgan vaqt'
status: Done
assignee:
  - '@claude'
created_date: '2026-10-10 15:13'
updated_date: '2026-10-10 18:09'
labels:
  - ai-island
  - ux
dependencies: []
references:
  - macos/AIIslandApp/Sources/AIIslandApp/main.swift
parent_task_id: TASK-53
priority: medium
type: enhancement
ordinal: 69000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Popoverda "LIMIT UNAVAILABLE" bir kartada 6 martagacha takrorlanadi; "924 managed files" va "LOCAL" belgisi limit kartasi uchun foydasiz. Barcha yozuvlar katta harfli monospace — oʻqish qiyin. Qayta tiklanish vaqti absolyut ("RESET 6:43 PM") koʻrsatiladi, holbuki `resetCountdown` yozilgan, lekin ishlatilmaydi.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Ikkala oyna ham mavjud boʻlmagan akkaunt uchun bitta qisqa qator chiqadi (masalan, "Limit hali maʼlum emas")
- [x] #2 Managed files soni va LOCAL/OFFLINE belgisi popoverdan olib tashlanadi (kerak boʻlsa Settings da qoladi)
- [x] #3 Captionlar oddiy registr va proporsional shriftda, raqamlar monospacedDigit
- [x] #4 Reset nisbiy vaqtda ("2s 15d qoldi"), absolyut vaqt tooltipda
- [x] #5 Popover snapshot regressiyasi yangilanadi va rasm koʻrib chiqiladi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ClaudeSessions: ResetCountdown — qayta tiklanishgacha qolgan vaqt matni ('5m', '2h 15m', '3d 4h', oʻtgan boʻlsa 'now'), unit testlar bilan. AppDelegate.resetCountdown oʻrniga shu ishlatiladi.
2. usageBarViews: caption '5H · 96% used · resets in 2h 15m' (oddiy registr, monospacedDigitSystemFont medium). Absolyut vaqt tooltip'da ('Resets at 6:43 PM', 24 soatdan uzoq boʻlsa sana bilan). ' · LAST KNOWN' → ' · last known'.
3. Ikkala oyna yoʻq boʻlsa bitta qator 'Limits not available yet' (barsiz). Faqat bittasi yoʻq boʻlsa '7D · not available' va xira bar. Codex va har bir Claude manbasi uchun.
4. Provider kartasidan 'LOCAL/OFFLINE' belgisi va 'N managed files' satri olib tashlanadi (Settings da qoladi). Oʻrnatilmagan boʻlsa 'Not detected' qoladi.
5. Sarlavha 'LIVE AI LIMITS' (monospace) → 'Live AI limits' (system semibold), '  · NOW' → ' · now', islandSummary captioni oddiy shriftda.
6. Regressiyalar: usage va accounts dagi label tekshiruvlari yangi matnga, yangi tekshiruvlar (LOCAL/managed files yoʻq, katta harfli caption yoʻq, reset nisbiy + tooltip absolyut, ikkala oyna yoʻq — bitta qator). popover.png koʻrib chiqiladi.
7. swift test, uchala regressiya, release build va skrinshot. Interfeys matnlari inglizcha qoladi (tarjima TASK-53.16 da).
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Popover: hech qaysi oyna maʼlum boʻlmagan manba uchun bitta 'Limits not available yet' qatori (Codex birinchi javobgacha 'Loading limits…'). Faqat bitta oyna yoʻq boʻlsa '7D · not available' va xira bar. LOCAL/OFFLINE belgisi va 'N managed files' satri olib tashlandi (Settings da qoladi, oʻrnatilmagan provider uchun 'Not detected' qoladi). Captionlar oddiy registrda, monospacedDigitSystemFont: '5H · 40% used · resets in 2h 15m'. Absolyut vaqt tooltipda ('Resets at …', 24 soatdan uzoq boʻlsa sana bilan). Sarlavha 'Live AI limits', '· now', '· last known'. Ishlatilmagan resetCountdown/resetFormatter oʻrniga ClaudeSessions.ResetCountdown (2 unit test).
Qoʻshimcha: bar boʻlmaganda karta torayib ketardi, endi karta 324pt ga qotirilgan. 124pt minimal balandlik olib tashlandi, karta va popover balandligi kontentga moslashadi.
Tekshiruv: swift test 54/54; settings 104, usage 37, accounts 30 PASS (yangi: nisbiy reset matni, tooltip absolyut va sana bilan, katta harfli caption yoʻq, proporsional shrift, LOCAL/managed files yoʻq, bitta qator, Loading, karta kengligi). usage.popover.png va accounts.popover.png koʻzdan kechirildi. Foydalanuvchi fayllari shasum oʻzgarmadi. Release build: haqiqiy popover skrinshoti haqiqiy maʼlumotlar bilan toʻgʻri.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Popover soddalashtirildi. Maʼlumotsiz manba uchun 'LIMIT UNAVAILABLE' takrorlari oʻrniga bitta qator chiqadi. LOCAL/OFFLINE belgisi va managed files soni olib tashlandi. Captionlar oddiy registr va proporsional shriftda. Reset 'resets in 2h 15m' koʻrinishida, absolyut vaqt tooltipda. Kartalar kontentga moslashadi. swift test (54), uchala regressiya, popover rasmlari va haqiqiy ilova skrinshoti bilan tekshirildi.
<!-- SECTION:FINAL_SUMMARY:END -->
