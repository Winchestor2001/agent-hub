---
id: TASK-53.11
title: Codex limitlarini soʻrash intervalini kamaytirish
status: Done
assignee:
  - '@claude'
created_date: '2026-10-10 15:13'
updated_date: '2026-10-10 18:41'
labels:
  - ai-island
  - ux
dependencies: []
references:
  - macos/AIIslandApp/Sources/AIIslandApp/main.swift
parent_task_id: TASK-53
priority: medium
type: enhancement
ordinal: 71000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`CodexUsageReader` har 4 soniyada yangi `codex app-server` jarayonini ishga tushiradi (ichida 1s sleep va 2s timeout). Bu batareya va CPU uchun ogʻir, limitlar esa bunchalik tez oʻzgarmaydi. Claude keshi lokal fayl boʻlgani uchun tez oʻqilishi mumkin.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Codex soʻrovi fon rejimida 30–60s intervalda, popover ochilganda va Refresh bosilganda darhol bajariladi
- [x] #2 Claude lokal keshi tezroq (masalan, 4–5s) oʻqilaverishi mumkin va Codex soʻroviga bogʻliq emas
- [x] #3 Bir vaqtda bittadan ortiq Codex jarayoni ishlamaydi
- [x] #4 Usage regressiyasidagi interval tekshiruvi yangi qiymatlarga moslashtiriladi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Taymer 4 soniyalik tick boʻlib qoladi (usageTickInterval): har tickda Claude keshi oʻqiladi.
2. Codex soʻrovi tickda faqat oxirgi soʻrov boshlanganidan codexRefreshInterval (45 s) oʻtgan boʻlsa yuboriladi; ikkala interval regressiya uchun oʻzgaruvchi.
3. Popover ochilishi va Refresh tugmasi refreshCodexUsage() orqali darhol (majburiy) soʻraydi; isCodexUsageLoading himoyasi bir vaqtda faqat bitta jarayonni qoldiradi.
4. Usage regressiyasi qisqa intervallar bilan: Claude har tickda, Codex intervaldan tez emas, popover ochilganda va qoʻlda darhol, parallel soʻrov takrorlanmaydi.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Taymer 4 soniyalik tick (usageTickInterval) boʻlib qoldi va har tickda Claude keshini oʻqiydi. Codex tickda faqat oxirgi soʻrov boshlanganidan 45 s (codexRefreshInterval) oʻtgach soʻraladi. Ishga tushish, popover ochilishi va Refresh refreshCodexUsage() orqali darhol soʻraydi. isCodexUsageLoading himoyasi saqlandi.
Tekshiruv: swift test 54 ta; regressiyalar settings 104, usage 44 (3 marta), accounts 30 PASS; ~/.claude/settings.json va ~/.codex/config.toml shasum oʻzgarmadi. Release ilovada 110 s kuzatuv: app-server --stdio jarayoni 48 s oraliqda, bir vaqtda bittadan.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
AI Island endi Codex limitlarini fonda 4 soniyada emas, 45 soniyada bir soʻraydi (tick tufayli amalda 45–49 s). Popover ochilganda va Refresh bosilganda soʻrov darhol yuboriladi. Claude keshi har 4 soniyada Codexdan mustaqil oʻqiladi. Bir vaqtda faqat bitta Codex jarayoni ishlaydi. Usage regressiyasi qisqartirilgan intervallar bilan tick, interval, darhol soʻrov va standart qiymatlarni tekshiradi.
<!-- SECTION:FINAL_SUMMARY:END -->
