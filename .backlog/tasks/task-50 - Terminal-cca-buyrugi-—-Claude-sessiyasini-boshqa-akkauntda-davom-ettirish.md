---
id: TASK-50
title: 'Terminal: cca buyrug''i — Claude sessiyasini boshqa akkauntda davom ettirish'
status: Done
assignee:
  - '@claude'
created_date: '2026-10-08 11:37'
updated_date: '2026-10-08 11:43'
labels:
  - ai-island
  - accounts
  - cli
dependencies: []
ordinal: 57000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Foydalanuvchi AI Island'ni sessiya yaratish uchun kam ishlatadi; asosan terminalda ishlaydi. Bitta akkaunt limiti tugaganda o'sha sessiyani (session id bo'yicha) ikkinchi akkauntda terminaldan davom ettirishni xohlaydi. Tanlovlar: buyruq nomi 'cca'; oddiy 'claude' (global ~/.claude) sessiyalari ham manba bo'la oladi (~/.claude faqat o'qiladi, login/tokenlarga tegilmaydi); o'tishda session id o'zgarmaydi (transkript nusxalanib 'claude --resume <id>'). Akkauntlar AI Island bazasidan (~/.claude-manager) olinadi.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 'cca ls' akkauntlarni (raqam, nom, holat, obuna, usage % va reset) va joriy papkadagi sessiyalarni (qisqa id, sarlavha, oxirgi ishlatilgan akkaunt/global, vaqt, ochiqligi) ko'rsatadi
- [x] #2 'cca <N|nom>' joriy papkada shu akkaunt bilan yangi Claude ochadi; kirilmagan akkauntda 'cca login N' maslahati bilan to'xtaydi; limiti tugagan akkauntda ogohlantirib to'xtaydi
- [x] #3 'cca <N> <session-id yoki prefiks>' sessiya transkriptini (global yoki boshqa akkauntdan, eng yangisi) maqsad akkauntga nusxalaydi va o'sha id bilan, sessiyaning o'z papkasida 'claude --resume' qiladi; '-c' joriy papkadagi oxirgi sessiyani oladi; noaniq prefiks yoki hali ochiq sessiya aniq xabar bilan rad etiladi
- [x] #4 'cca login N' shu terminalda akkauntga kirishni bajaradi; cca orqali ochilgan Claude statusline'i akkaunt usage'ini AI Island bazasiga yozadi
- [x] #5 ~/.local/bin/cca shim o'rnatish skripti bor (foydalanuvchi ruxsati bilan o'rnatiladi); XCTest'lar (nusxalash, prefiks, ochiq sessiya, -c, akkaunt tanlash) va mavjud testlar o'tadi, release build
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ClaudeSessions/AccountCLI.swift: manbalar (global ~/.claude + har akkaunt claude-config), papka kodlash (alfanumerik bo'lmagan -> '-'), transkript qidirish (id/prefiks, eng yangi mtime), sarlavha (customTitle/aiTitle/birinchi user xabari), cwd (transkriptdan), ochiq sessiya (<config>/sessions/<pid>.json + kill(pid,0)), nusxalash (jsonl + <id>/ papka, atomik).
2. Buyruqlar: ls, <N|nom> [id|-c] [claude args], login N, help. Akkaunt: rowid tartibida raqam yoki nom. Auth: checkAuthentication; limit: store.usage (stale emas, reset kelmagan).
3. Ishga tushirish: execve claude, env = adapter.environment(account), cwd = sessiya papkasi, --settings bilan statusLine -> '--cca-statusline <root> <account>' (usage_snapshots'ga yozadi, 'Claude · nom · N%' chiqaradi).
4. handleCommandLine'ga --cca va --cca-statusline; scripts/install-cca.sh (~/.local/bin/cca shim; ruxsat bilan ishga tushiriladi).
5. XCTest: fake config dirlar bilan topish/nusxalash/prefiks/ochiq sessiya/-c/akkaunt tanlash; swift test, release build.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Tekshiruv: AccountCLITests 6/6 (kodlash, akkaunt tanlash, yangi sessiya env/--settings, global->1->2 nusxalash bir xil id va sidecar papka bilan, -c, prefiks xatolari, ochiq sessiya rad, signed out -> 'cca login 2', 100% limit rad, statusline usage yozadi); swift test 28/28. claude 2.1.293 bilan prob: vaqtinchalik CLAUDE_CONFIG_DIR'ga nusxalangan transkriptni --resume topdi (keyin 'Not logged in'), yo'q id esa 'No conversation found'. Shim scratchpad'ga o'rnatilib 'cca help/ls' va xato kodlari tekshirildi; haqiqiy ~/.local/bin/cca foydalanuvchi ruxsatidan keyin o'rnatiladi. SessionManager.recordUsage ajratildi (StatusLine hook va cca statusline umumiy). Sarlavha: customTitle/aiTitle, aks holda isMeta bo'lmagan va '<' bilan boshlanmagan birinchi user xabari.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Terminal uchun 'cca' buyrug'i qo'shildi (AI Island binary'si --cca rejimi + scripts/install-cca.sh shim): cca ls, cca N, cca N <id|prefiks>, cca N -c, cca login N. Sessiya transkripti (global ~/.claude yoki boshqa akkauntdan, eng yangisi) maqsad akkauntga o'sha id bilan nusxalanib 'claude --resume' qilinadi; ~/.claude faqat o'qiladi. cca orqali ochilgan Claude statusline'i akkaunt usage'ini bazaga yozadi. Tekshiruv: AccountCLITests 6/6, swift test 28/28, real claude bilan --resume prob, release build.
<!-- SECTION:FINAL_SUMMARY:END -->
