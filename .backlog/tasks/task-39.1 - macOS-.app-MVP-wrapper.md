---
id: TASK-39.1
title: macOS .app MVP wrapper
status: Done
assignee:
  - '@codex'
created_date: '2026-09-28 06:31'
updated_date: '2026-09-28 08:14'
labels:
  - desktop
  - client
dependencies: []
parent_task_id: TASK-39
type: feature
ordinal: 44000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Birinchi slice: mavjud Agent Hub server va React UI ni macOS oynasida ochadigan yengil native wrapper. Bu bosqichda backend embed qilinmaydi va launchd/install oqimi o‘zgarmaydi; app faqat lokal Agent Hub health holatini tekshiradi va UI ni WKWebView ichida ko‘rsatadi.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Repo ichida macOS app manbalari bor va Swift build bilan yig‘iladi
- [x] #2 Yig‘ish skripti Agent Hub.app bundle yaratadi
- [x] #3 App http://127.0.0.1:8700 ni WKWebView ichida ochadi
- [x] #4 Backend health ishlamasa retry/open browser/terminalda ishga tushirish bo‘yicha tushunarli ekran ko‘rinadi
- [x] #5 README yoki dev hujjatda .app build va ishga tushirish bo‘limi bor
- [x] #6 Mavjud make check yoki mos smoke testlar regressiyasiz o‘tadi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Repo ichidagi mavjud build/install konvensiyalarini tekshirib, Swift/AppKit wrapper uchun eng kichik papka tuzilmasini tanlash.
2. Native macOS app: WKWebView oynasi, backend health tekshiruvi, offline status ekrani, retry va brauzerda ochish tugmalari.
3. scripts/build-macos-app.sh orqali Swift executable ni .app bundle ichiga joylash, Info.plist va minimal assetlarni qo‘shish.
4. README ga build/run bo‘limini qo‘shish.
5. swift build, build script va mavjud testlardan zarur qismini ishga tushirib tekshirish.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented Swift/AppKit WKWebView wrapper under macos/AgentHubApp, added scripts/build-macos-app.sh, Makefile macos-app target, .gitignore entries, and README section. Verification: swift build --package-path macos/AgentHubApp passed; scripts/build-macos-app.sh built dist/Agent Hub.app; make macos-app passed; plutil showed AgentHubURL=http://127.0.0.1:8700 and NSAllowsLocalNetworking=true; file showed Contents/MacOS/AgentHub is Mach-O arm64; curl /api/health returned ok=true; open dist/Agent Hub.app succeeded and osascript returned application name AgentHub; make check passed (ruff, mypy, pytest 635, eslint, tsc, vitest 115). Screenshot/window introspection was not available in this environment (screencapture could not create image; System Events window query needs Accessibility permission), so AC #3 and #4 remain unchecked pending visual/manual UI verification.

Follow-up fix: WKWebView did not expose macOS screenshot paste as clipboardData.files, so screenshot temp paths could fall through to Codex and fail with Operation not permitted. Added native Cmd+V handling in AgentHubApp: file URLs and clipboard images are read by the app, sent to the web UI via agent-hub-native-paste-files, converted to File objects, and reused by the existing upload flow. Verification: swift build --package-path macos/AgentHubApp passed; make macos-app passed; web nativePaste focused tests passed; make check passed (pytest 635, vitest 118, lint/typecheck clean).

Second paste fix: added a normal macOS Edit menu (Copy/Paste/Select All) so plain text copy/paste routes through WKWebView correctly, and added an app-level local Cmd+V monitor that intercepts only file/image pasteboards before WebKit consumes them. Text-only paste is returned to the normal responder chain. Verification: swift build --package-path macos/AgentHubApp passed; make macos-app passed; nativePaste focused test passed; make check passed (pytest 635, vitest 118, lint/typecheck clean).

Third paste/drop fix: make macos-app now depends on frontend build so the backend serves the latest React bundle. Added terminal drag/drop handlers that upload dropped files through the same project upload flow. Added xterm custom key handler for Cmd/Ctrl+C when terminal text is selected, writing the selection to the clipboard while preserving Ctrl-C behavior when nothing is selected. Verification: web typecheck passed; focused vitest nativePaste+terminal protocol passed; make macos-app rebuilt frontend static and Agent Hub.app; make check passed (pytest 635, vitest 118, lint/typecheck clean).

Codex copy workaround: Codex CLI enables terminal mouse mode, so normal drag selection can be swallowed by the app and Cmd+C sees no xterm selection. Enabled xterm macOptionClickForcesSelection and added a toolbar Copy button that writes the current terminal selection to the clipboard. In Codex panes, use Option-drag to select text, then Cmd+C or the Copy toolbar button. Verification: web typecheck passed; focused i18n/model tests passed; make macos-app rebuilt frontend static and Agent Hub.app; swift build passed; make check passed (pytest 635, vitest 118, lint/typecheck clean).

Manual verification by user: rebuilt and opened Agent Hub.app, terminal text paste worked, screenshot/image/file paste and drag/drop worked after the frontend+native paste fixes, and Codex terminal text copy worked with Option-drag selection plus Cmd+C/Copy button workaround. AC #3 is now verified. AC #4 remains pending offline backend screen verification.

Manual verification by user: offline/backend-unavailable mode shows the described error/status text and is acceptable. AC #4 is now verified.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented a macOS Agent Hub.app MVP wrapper around the existing local backend/frontend, plus terminal paste/drop/copy fixes needed for WKWebView and Codex mouse mode. Verified with swift build, make macos-app, make check (pytest 635, vitest 118), and user manual testing of online UI, offline error screen, text paste, screenshot/file paste, drag/drop, and Codex copy workaround.
<!-- SECTION:FINAL_SUMMARY:END -->
