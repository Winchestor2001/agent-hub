---
id: TASK-48
title: 'AI Island: Claude Code limitlarini statusline keshidan ko''rsatish'
status: Done
assignee:
  - '@claude'
created_date: '2026-10-08 05:51'
updated_date: '2026-10-08 05:57'
labels:
  - ai-island
  - limits
dependencies: []
ordinal: 55000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Foydalanuvchi AI Island'da Claude Code 5 soatlik va haftalik limitlarini ko'ra olmayapti. Hozir Claude usage faqat AI Island o'zi ochgan (Claude accounts) sessiyaning statusline'idan keladi, oddiy terminaldagi `claude` sessiyalari uchun hech narsa ko'rinmaydi. Foydalanuvchining global statusline'i (~/.claude/statusline.sh) rate_limits'ni allaqachon ~/.claude/agent-hub-rate-limits.json ga yozib boradi ({captured_at, rate_limits.five_hour/seven_day: used_percentage, resets_at}); web Agent Hub uni services/limits.py da o'qiydi. AI Island ham shu keshni o'qishi kerak. ~/.claude/settings.json o'zgartirilmaydi, OAuth/Keychain o'qilmaydi.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Claude kartasida keshdagi 5H va 7D foizlari reset vaqti bilan chiziq ko'rinishida chiqadi; kesh yo'q, buzuq yoki bo'sh bo'lsa «LIMIT UNAVAILABLE»
- [x] #2 Island halqasi va kichik chizig'i Claude uchun keshdagi eng yuqori foizni ko'rsatadi; AI Island o'zi ochgan faol sessiya bo'lsa uning akkaunt usage'i ustun
- [x] #3 20 daqiqadan eski kesh «LAST KNOWN» deb belgilanadi; reset vaqti o'tgan oyna eski foiz bilan ko'rsatilmaydi
- [x] #4 Kesh avtomatik yangilanish (4 s) bilan birga qayta o'qiladi; ~/.claude/settings.json va kredensiallarga tegilmaydi
- [x] #5 Kesh parseri uchun swift testlar, native regression va release build muvaffaqiyatli; yangilangan app qayta ochiladi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ClaudeSessions moduliga ClaudeRateLimits.swift: ClaudeRateLimitWindow(usedPercent, resetsAt), ClaudeRateLimits(fiveHour, sevenDay, capturedAt, stale, maxPercent), ClaudeRateLimitCache.read(url:now:) — fayl yo'q/buzuq/bo'sh → nil; 0...100 dan tashqari qiymat rad; resets_at o'tgan oyna tashlanadi; captured_at 20 daqiqadan eski → stale. Default yo'l ~/.claude/agent-hub-rate-limits.json (statusline.sh shu yerga yozadi).
2. main.swift: claudeUsage holati, readClaudeUsage (regression uchun almashtiriladigan); refreshCodexUsage boshida kesh qayta o'qiladi (4 s timer bilan).
3. Claude kartasi: 5H/7D chiziqlari (usageBarViews, stale bo'lsa · LAST KNOWN), ostida akkaunt xulosasi bo'lsa qoladi; halqa/kichik chiziq: faol AI Island sessiyasi usage'i, aks holda kesh maxPercent; tooltip.
4. XCTest (parser holatlari), usage regression'ga Claude kesh tekshiruvi, swift build release, app qayta ochish va jonli keshni ko'zdan kechirish.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Tekshiruv: swift test — 21/21 (yangi ClaudeRateLimitsTests 5 ta: ikki oyna, yo'q/buzuq/bo'sh kesh, 0..100 dan tashqari, reset o'tgan oyna, 20 daqiqalik stale). --usage-regression-report 14/14 PASS (Claude 5H «LAST KNOWN», 7D «LIMIT UNAVAILABLE», halqa 0.55, Codex so'rovi osilganda ham Claude kartasi yangilanadi). --accounts-regression-report: «ring prefers account usage over the global cache» PASS; «Diagnostics contain session identities» FAIL — HEAD (1ec41fd) da ham FAIL, TASK-48 ga aloqasi yo'q. Release build (scripts/build-ai-island-app.sh) muvaffaqiyatli, app qayta ochildi; jonli kesh 5H 9% / 7D 8%. Qaror: Claude keshi Codex so'rovidan mustaqil — o'zgarsa darhol qayta chiziladi (rebuildUsageViews). ~/.claude/settings.json va statusline.sh o'zgartirilmadi.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
AI Island endi Claude Code 5H/7D limitlarini global statusline keshidan (~/.claude/agent-hub-rate-limits.json) o'qiydi: Claude kartasida reset vaqti bilan chiziqlar, eski kesh «LAST KNOWN», yo'q oyna «LIMIT UNAVAILABLE»; halqa va kichik chiziq faol AI Island sessiyasi bo'lmasa keshdagi maksimal foizni ko'rsatadi. Kesh 4 s timer bilan, Codex so'rovidan mustaqil qayta o'qiladi. Tekshiruv: swift test 21/21, usage regression 14/14, accounts regression'da ustunlik PASS (avvaldan bor diagnostika FAIL'i bundan mustaqil), release build va app qayta ochildi. settings.json/kredensiallarga tegilmadi.
<!-- SECTION:FINAL_SUMMARY:END -->
