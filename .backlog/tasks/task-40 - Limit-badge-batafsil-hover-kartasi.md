---
id: TASK-40
title: Limit badge batafsil hover kartasi
status: Done
assignee:
  - '@codex'
created_date: '2026-09-28 08:15'
updated_date: '2026-09-29 06:39'
labels:
  - client
dependencies: []
type: enhancement
ordinal: 47000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TopBar hozir Claude/Codex rate-limit holatini juda qisqa ko‘rsatadi (masalan, claude 7д 18%, codex 5ч 89%). Foydalanuvchiga 5 soatlik va 7 kunlik oynalar, reset vaqti, data yangilangan va eskirgan holati ko‘proq ko‘rinishi kerak, lekin TopBar ixcham qolishi kerak.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Claude va Codex uchun 5h va 7d oynalar mavjud bo‘lsa ikkalasi ham ko‘rinadi
- [x] #2 Badge hover yoki keyboard focus qilinganda kichik card/popover ko‘rinadi
- [x] #3 Card ichida 5h va 7d foizlari, reset vaqti, data yangilangan va stale holati ko‘rsatiladi
- [x] #4 Ma’lumot yo‘q bo‘lsa tushunarli unavailable card ko‘rinadi
- [x] #5 uz+ru i18n va frontend test/typecheck o‘tadi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Existing limits API shape and TopBar/LimitBadges rendering stays unchanged at data layer.
2. Extend web/src/limits/model.ts with formatting helpers for percent, reset time/date, updated age, and summary rows.
3. Replace per-window-only hover title with an accessible hover/focus popover per agent in LimitBadges.
4. Add uz/ru strings and CSS for compact cards that do not disturb TopBar layout.
5. Add/update vitest coverage for limit formatting and run focused frontend checks plus make check.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented detailed limit hover/focus card in web/src/components/LimitBadges.tsx with formatting helpers in web/src/limits/model.ts, uz/ru i18n strings, and CSS popover styling. Verification passed: cd web && npm run typecheck; cd web && npm test -- limits/model.test.ts i18n/messages.test.ts; cd web && npm run lint; make macos-app; make check (635 pytest passed, 121 vitest passed). Manual UI hover/focus confirmation still needed before checking interactive ACs.

Added web/src/components/LimitBadges.test.tsx to render the limit badges through React and verify the tooltip/popover markup, aria-describedby links, 5h/7d rows, reset text, updated text, stale detail, and unavailable card. Fresh verification after this test: cd web && npm test -- LimitBadges.test.tsx limits/model.test.ts i18n/messages.test.ts (25 passed); cd web && npm run typecheck; cd web && npm run lint; make macos-app; make check (635 pytest passed, 123 vitest passed).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented compact Claude/Codex limit badges with detailed hover/focus popovers for 5h and 7d windows, reset time, updated age, stale state, and unavailable data. Verified with component/model/i18n tests, full typecheck/lint, macOS app build, and make check.
<!-- SECTION:FINAL_SUMMARY:END -->
