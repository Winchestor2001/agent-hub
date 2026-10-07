---
id: TASK-44
title: 'AI Island: konfiguratsiya royxati va editor layoutini tuzatish'
status: Done
assignee:
  - '@codex'
created_date: '2026-09-30 19:03'
updated_date: '2026-09-30 19:27'
labels: []
dependencies: []
type: bug
ordinal: 51000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Skills va boshqa konfiguratsiya kategoriyalarida kop fayl aniqlansa ham UI faqat bittasini korsatmoqda. config.toml editorining korinishi ham tekshirilishi kerak.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Kop faylli kategoriyalarda royxatning bir nechta qatori korinadi va oxirgi faylgacha scroll qilib tanlash mumkin
- [x] #2 Tanlangan fayl editorida togri kontent korinadi, jumladan config.toml
- [x] #3 Oyna resize va close/reopen sinovlari layout hamda oldingi crash regressionidan otadi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Native regressionga viewport va row geometry tekshiruvlarini qoshish. 2. Royxat layoutini tuzatish. 3. Birinchi, ortadagi va oxirgi fayl tanlovi hamda config.toml editorini tekshirish. 4. Build va yangilangan appni restart qilish.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Pre-fix geometry regression: Codex Skills document height 11250, viewport origin 0, visible rows 0. Replaced manual unflipped NSStackView document with native NSTableView and relative-path cells. Set sidebar minimum width 220 and preferred width 260; initial table implementation compressed sidebar to 52 on resize, caught and corrected by regression. Enabled vertical text resizing with unbounded text container. Final report /private/tmp/ai-island-layout-verified.txt passes 36 category close/reopen cycles, two content sizes 760x460 and 1200x760, first/middle/last selection and scroll, matching file contents, complete text glyph layout, and Command-Q. Skills visible rows 13 at small size and 22 at large size; counts remain Codex 361 and Claude 650. config.toml is one global file and editor content is verified.

Final verified large-window Skills viewport contains 23 rows (correction to the earlier 22 estimate). Updated production instance PID 24296 is running; no new crash report appeared.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Fixed clipped file lists and sidebar resizing using native NSTableView. Verified file selection, editor contents including config.toml, full text layout, and close/reopen across all categories with native regression. Rebuilt app and restarted the previous process to load the updated UI.
<!-- SECTION:FINAL_SUMMARY:END -->
