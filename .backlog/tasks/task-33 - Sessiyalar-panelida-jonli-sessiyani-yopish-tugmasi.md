---
id: TASK-33
title: Sessiyalar panelida jonli sessiyani yopish tugmasi
status: Done
assignee:
  - '@claude'
created_date: '2026-09-16 06:56'
updated_date: '2026-09-16 07:02'
labels:
  - client
dependencies: []
ordinal: 33000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-32 da vazifa Done bo'lganda sessiyani yopish taklifi qo'shildi, lekin vazifaga bog'lanmagan yoki boshqa sabab bilan keraksiz qolgan jonli sessiyani UI orqali to'xtatib bo'lmaydi: sessiyalar panelida faqat tugagan pane'ni ro'yxatdan olib tashlash va o'tgan sessiyalarni o'chirish bor. Backendda POST /api/sessions/{pane_id}/kill va frontendda useKillSessions allaqachon bor — jonli sessiya qatoriga tugma kerak. Agent ishlayotgan bo'lishi mumkinligi uchun tasdiq so'ralsin.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Jonli sessiya qatorida yopish tugmasi bor (aria-label bilan), faqat shu qatorga ta'sir qiladi
- [x] #2 Tugma bosilganda qator ichida tasdiq so'rovi chiqadi; bekor qilinsa hech narsa yopilmaydi
- [x] #3 Tasdiqlansa pane POST /api/sessions/{pane_id}/kill bilan yopiladi, xato qatorda ko'rinadi, ro'yxat va doska yangilanadi
- [x] #4 Yangi matnlar uz va ru lug'atlarida bor; web testlari, typecheck va lint o'tadi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. queries.ts: useInvalidateSessions va useKillSessions projectId'ni null qabul qilsin (null — barcha board/task so'rovlari yangilanadi), sessiyalar paneli loyihalararo bo'lgani uchun.
2. SessionsPanel/LiveList: qator ichida yopish tugmasi (icon-button) + .confirm bloki (matn, Bekor / Yopish, ErrorText).
3. i18n uz+ru: sessions.kill, sessions.kill_confirm, sessions.kill_yes, sessions.killing, sessions.kill_failed.
4. npm test + typecheck + lint, build; commit.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Bajarildi: LiveList qatoriga ■ tugmasi (aria-label sessions.kill) va qator ichida .confirm bloki; tasdiqlanganda useKillSessions([pane.id]). queries.ts: useInvalidateSessions/useKillSessions endi projectId null bo'lishini qabul qiladi — null da barcha ['board'] va ['task'] so'rovlari yangilanadi (sessiyalar paneli loyihalararo). Tugagan sessiyalardagi × (ro'yxatdan olib tashlash) bilan chalkashmasligi uchun jonli sessiyada ■ ishlatildi.

Tekshiruv: npm test 92 test, typecheck, lint toza; build src/agent_hub/static ga qilindi.

Foydalanuvchi 8700 dagi ilovada tekshirdi: jonli sessiya qatoridagi tugma va tasdiq so'rovi ishlaydi, sessiya yopiladi.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Sessiyalar panelidagi har bir jonli sessiya qatoriga yopish tugmasi (■, aria-label sessions.kill) va qator ichidagi tasdiq bloki qo'shildi; tasdiqlanganda pane POST /api/sessions/{id}/kill bilan yopiladi, xato o'sha qatorda ko'rinadi, keyin sessiyalar/loyihalar/doskalar yangilanadi. useInvalidateSessions va useKillSessions endi projectId null bo'lishini qabul qiladi (panel loyihalararo). uz+ru ga sessions.kill* kalitlari. Tekshiruv: 92 web testi, typecheck, lint toza; UI ni foydalanuvchi brauzerda sinab ko'rdi. Commit: 7629b7c.
<!-- SECTION:FINAL_SUMMARY:END -->
