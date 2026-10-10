---
id: TASK-53.5
title: 'Island: nomaʼlum usage uchun 100% chiziq va "0% / nomaʼlum" farqi'
status: Done
assignee:
  - '@claude'
created_date: '2026-10-10 15:13'
updated_date: '2026-10-10 15:21'
labels:
  - ai-island
  - ux
dependencies: []
references:
  - macos/AIIslandApp/Sources/AIIslandApp/main.swift
parent_task_id: TASK-53
priority: high
type: bug
ordinal: 65000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`compactProviderCell` Claude usage nomaʼlum, lekin konfiguratsiya mavjud boʻlsa status barni `progress = 1` bilan toʻla chizadi — bu "limit tugadi" deb oʻqiladi. Codex limitlarini oʻqib boʻlmaganda halqa boʻsh qoladi va 0% bilan farqlanmaydi (skrinshotda Codex halqasi aynan shunday). Limit monitori uchun nomaʼlum holat aniq koʻrinishi shart.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Usage nomaʼlum boʻlsa hech qachon toʻla yoki deyarli toʻla chiziq/halqa chizilmaydi
- [x] #2 Nomaʼlum/oʻqib boʻlmagan holat 0% dan vizual farq qiladi (masalan, punktir halqa yoki "—"), yuklanish holati esa alohida
- [x] #3 Tooltipda nima uchun nomaʼlumligi (yuklanmoqda / CLI topilmadi / maʼlumot hali yoʻq) yoziladi
- [x] #4 Regressiya: Claude usage nil + konfiguratsiya mavjud holatda progress 1 emas
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Island katakchasi uchun aniq holat: known(foiz) / loading / unknown(sabab). Codex: usage bor → known; birinchi soʻrov tugamagan → loading; soʻrov tugagan, lekin maʼlumot yoʻq → unknown. Claude: claudeIslandPercent bor → known, aks holda unknown.
2. UsageRingView: unknown holatda punktir track (yoy yoʻq); loading — mavjud nuqta; known 0% — toʻliq track, yoysiz.
3. Kichik status bar alohida CompactUsageBar klassiga: progress nil (nomaʼlum) → toʻldirilmaydi va xiraroq; known 0% → boʻsh; progress = 1 fallback va 0.05/0.02 minimal toʻldirish olib tashlanadi.
4. Sabab tooltipi katakcha, halqa va logoga beriladi: loading / CLI topilmadi (CodexUsageReader va ClaudeAuthReader bilan bir xil executable qidiruvi) / maʼlumot hali yoʻq. Matnlar hozircha inglizcha (tarjima — TASK-53.16).
5. Usage regressiyasiga checklar: Claude kesh nil + konfiguratsiya bor → bar progress nil (1 emas), halqa unknown; Codex birinchi soʻrov paytida loading, muvaffaqiyatsiz soʻrovdan keyin unknown + tooltip sababi.
6. swift test, usage + accounts regressiyalari, release build, app qayta ochiladi va island skrinshoti koʻriladi.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Codex loading holati endi isCodexUsageLoading emas, didFinishCodexUsageRequest bilan aniqlanadi — har 4 soniyalik pollingda halqa nuqtasi miltillamaydi. Tekshiruv: swift test (17 + 28 XCTest, 0 xato); --usage-regression-report 19/19 PASS, shu jumladan 5 ta yangi check (Codex loading, Claude unknown bar nil + tooltip, Codex unknown + sabab, 0% unknowndan farqli); --accounts-regression-report 22 PASS, 0 FAIL; release build qayta ochildi, island skrinshotida Codex ~1% va Claude ~65% toʻgʻri chizilgan.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Island katakchasi endi aniq holatga ega: known(foiz) / loading / unknown(sabab). Nomaʼlum usage punktir halqa va toʻldirilmagan xira chiziq bilan koʻrsatiladi, 0% esa toʻliq trek boʻlib yoysiz qoladi. Claude uchun progress = 1 fallback hamda 0.05/0.02 minimal toʻldirish olib tashlandi; kichik chiziq alohida CompactUsageBar klassiga koʻchirildi. Katakcha, halqa va logo tooltiplari sababni koʻrsatadi (loading / CLI topilmadi / limitlar hali yoʻq), maʼlum Codex holatida esa 5H/7D foizlari chiqadi. Tekshiruv: swift test, usage regressiyasi (19/19 PASS, 5 ta yangi check), accounts regressiyasi (22 PASS), release build va island skrinshoti.
<!-- SECTION:FINAL_SUMMARY:END -->
