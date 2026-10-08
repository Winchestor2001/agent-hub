---
id: TASK-49
title: 'AI Island: Claude akkauntlar oynasini kartalar ko''rinishida qayta loyihalash'
status: Done
assignee:
  - '@claude'
created_date: '2026-10-08 06:08'
updated_date: '2026-10-08 06:17'
labels:
  - ai-island
  - accounts
dependencies: []
ordinal: 56000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Foydalanuvchi uchun Claude Accounts & Sessions oynasida akkaunt qo'shish va boshqarish tushunarsiz: akkaunt bitta popup'da tanlanadi, Sign in/Check auth tugmalari yashirin tanlovga ishlaydi, holat alohida matnda, sessiya yaratish ham shu popup'dagi akkauntni yashirin ishlatadi, qayta nomlash/o'chirish yo'q, 7 ta texnik tugma bir qatorda. Foydalanuvchi tanlovi: akkaunt kartalari tuzilishi, UI inglizcha qoladi, 'Add account' dan keyin darhol Terminal'da sign-in ochiladi.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Har akkaunt o'z kartasida: nom, holat (Ready/Signed out/Active), obuna, usage chizig'i va reset vaqti; karta o'z tugmalariga ega (Sign in… yoki Check, va ⋯ menyu: Rename…, Sign in again…, Remove…)
- [x] #2 Add account: nom so'raladi, akkaunt yaratiladi va darhol shu akkaunt uchun Terminal'da sign-in ochiladi; 2 ta akkaunt bo'lganda tugma o'chiq va sababi ko'rsatiladi
- [x] #3 Rename akkaunt nomini o'zgartiradi; Remove tasdiq so'raydi, sessiyalarda ishlatilgan akkauntni o'chirmaydi (tushunarli xabar), ishlatilmaganini claude auth logout (best-effort) bilan chiqarib, config papkasini Trash'ga ko'chiradi
- [x] #4 Sessiyalar alohida bo'limda kartalar bilan: New session… dialogida loyiha, nom va akkaunt aniq tanlanadi; har sessiya kartasida Stop va 'Continue with ▾' (boshqa akkauntlar ro'yxati); Readiness/Cancel pending/Recover ⋯ menyuda
- [x] #5 Tarix va diagnostika tanlangan sessiya uchun pastdagi bo'limda; native accounts regression yangi UI uchun yangilanib to'liq PASS (diagnostika tekshiruvi ham), swift test, release build o'tadi va app qayta ochiladi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Store: renameAccount(id,name); SessionManager.removeAccount(id): physical_sessions/session_locks bo'lsa SessionError.accountInUse; aks holda claude auth logout (best-effort, akkaunt CLAUDE_CONFIG_DIR bilan), usage_snapshots/mcp_readiness/accounts qatorlari o'chiriladi, accounts/<id> papkasi root ichida ekani tekshirilib Trash'ga ko'chiriladi. XCTest.
2. ClaudeAccountsWindow qayta yoziladi (scroll ichida vertikal stack): sarlavha + Add account; akkaunt kartalari (holat nuqtasi, nom, obuna·holat, usage bar + reset, Sign in…/Check, ⋯ pulldown: Rename…, Sign in again…, Remove…); bo'sh holat matni.
3. Sessions bo'limi: New session… (NSAlert accessory: loyiha + Choose…, nom, akkaunt popup); sessiya kartalari (loyiha·nom, holat, akkaunt, branch; Stop, Continue with ▾ pulldown, ⋯: Readiness, Cancel pending launch, Recover stopped session); kartani bosish tanlaydi.
4. Pastda tanlangan sessiya uchun Handoff history va Developer diagnostics (ikkalasi ham ko'rinadi, tab emas — diagnostika regression FAIL'ini ham yopadi); xabar qatori.
5. islandSummary/islandUsage/continueSuggestedAccount API saqlanadi. Accounts regression yangi kontrollarga moslanadi, rename/remove/add-disabled tekshiruvlari qo'shiladi; swift test, release build, app qayta ochish.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Tekshiruv: native accounts regression 18/18 PASS (oldingi 'Diagnostics contain session identities' FAIL yopildi — tarix va diagnostika endi yonma-yon); yangi tekshiruvlar: kartalar, Check/Sign in…, ⋯ menyu, Add 2 ta akkauntda o'chiq, rename, remove (bo'sh slot), ishlatilgan akkaunt saqlanadi, Add account → nom → darhol login .command ochiladi (stub orqali). swift test 22/22, usage regression 14/14, release build, app qayta ochildi. removeAccount yo'l tekshiruvi /private prefiksi uchun ikki tomonni normallashtiradi. Snapshot'da fon shaffof bo'lgani uchun scroll fonini windowBackgroundColor qildim.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Claude Accounts oynasi kartalar ko'rinishida qayta yozildi: har akkaunt kartasida holat, obuna, usage chizig'i, Sign in…/Check va ⋯ (Rename…, Sign in again…, Remove…); Add account nom so'rab darhol Terminal sign-in ochadi, 2 ta akkauntda o'chiq. Sessiyalar alohida kartalar bilan (New session… dialogi, Stop, Continue with ▾, ⋯). Backend: Store.renameAccount, SessionManager.removeAccount (ishlatilgan akkauntni rad etadi, best-effort auth logout, papkani Trash'ga). Tekshiruv: accounts regression 18/18, usage 14/14, swift test 22/22, release build.
<!-- SECTION:FINAL_SUMMARY:END -->
