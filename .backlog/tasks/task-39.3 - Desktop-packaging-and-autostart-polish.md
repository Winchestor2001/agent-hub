---
id: TASK-39.3
title: Desktop packaging and autostart polish
status: Done
assignee:
  - '@codex'
created_date: '2026-09-28 06:39'
updated_date: '2026-09-29 07:01'
labels:
  - desktop
  - client
dependencies:
  - TASK-39.1
parent_task_id: TASK-39
type: feature
ordinal: 46000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
MVP va desktop controls ishlagandan keyin .app ni kundalik ishlatishga tayyorlash kerak: icon, bundle metadata, release artifact, launchd bilan mos autostart, update/install oqimlariga ta’sirini aniq hujjatlash.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Agent Hub.app icon, bundle identifier va version metadata bilan yig‘iladi
- [x] #2 dist yoki release artifact yaratish jarayoni hujjatlashtirilgan
- [x] #3 Autostart/install oqimi mavjud launchd servislariga zid kelmaydi
- [x] #4 Upgrade yoki rebuild vaqtida foydalanuvchi ma’lumotlariga tegilmasligi tekshirilgan
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Current macOS app build script and Info.plist metadata audit: icon support, bundle identifiers, version source, and dist output. 2. Add a generated app icon asset and wire CFBundleIconFile/Resources so Agent Hub.app has a visible icon. 3. Add a release artifact target/script that rebuilds the app and creates a portable zip without touching user data. 4. Document install/autostart/rebuild behavior in README, including launchd compatibility and user data safety. 5. Verify with plutil/Swift build/make macos-app, inspect bundle contents, and run make check.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented packaging polish: generated AgentHub.icns icon during app build, wired CFBundleIconFile, kept bundle identifier local.agent-hub.app and pyproject version metadata, added make macos-release via scripts/package-macos-app.sh, and documented release/autostart/rebuild behavior in README. Verification evidence: make macos-release produced dist/AgentHub-macos-0.1.0.zip; plutil showed CFBundleIconFile AgentHub, CFBundleIdentifier local.agent-hub.app, CFBundleShortVersionString 0.1.0, and CFBundleVersion 0.1.0; ls showed AgentHub.icns and zip exist; unzip -l showed the zip contains only Agent Hub.app bundle files; make check passed with 635 pytest selected passing and 124 vitest passing.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added production packaging polish for Agent Hub.app: generated macOS icon, bundle metadata wiring, release zip target, and README documentation for release artifact, launchd/autostart compatibility, and rebuild user-data safety. Verified with make macos-release, Info.plist/icon/zip inspection, and make check.
<!-- SECTION:FINAL_SUMMARY:END -->
