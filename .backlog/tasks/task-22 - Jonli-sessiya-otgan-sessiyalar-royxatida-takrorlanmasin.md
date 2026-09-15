---
id: TASK-22
title: Jonli sessiya o'tgan sessiyalar ro'yxatida takrorlanmasin
status: Done
assignee:
  - '@claude'
created_date: '2026-09-15 14:46'
updated_date: '2026-09-15 15:29'
labels:
  - backend
  - client
dependencies: []
ordinal: 22000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-12 qabulida kuzatildi: jonli Claude sessiyasi Sessiyalar panelida «Jonli agentlar» va «O'tgan sessiyalar» ro'yxatida bir vaqtda ko'rinadi (KanBot pane'ida session_id bo'sh bo'lgan). Hozir o'tganlar ro'yxatida faqat «Davom ettirish» bloklanadi, ammo bitta sessiya ikki joyda chiqib, chalkashlik tug'diradi.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Jonli pane'ga mos keladigan sessiya o'tgan sessiyalar ro'yxatida ko'rsatilmaydi, jumladan pane session_id'si bo'sh bo'lgan holatda
- [x] #2 Pane tugagach sessiya o'tganlar ro'yxatida qayta paydo bo'ladi va davom ettirish mumkin
- [x] #3 Boshqa papkadagi yoki boshqa agentning sessiyasi noto'g'ri yashirilmaydi; holatlar testlar bilan yopilgan
- [x] #4 Haqiqiy Claude sessiyasi bilan UI'da tekshirilgan
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Topilma: KanBot pane.session_id faqat karta sessiyalarida to'ladi; qo'lda ochilgan claude pane'larida doim bo'sh. Resume pane'lari argv orqali aniqlanadi (open_session_ids).
1. services/linking.py: live_session_ids(panes, sessions) — open_session_ids + ID'si noma'lum tirik pane'lar uchun taxminiy bog'lash: agent bir xil, cwd realpath bo'yicha teng, runner_id (ikkalasida bo'lsa) teng, session.started_at >= pane.started_at - 5s. Pane'lar eng yangisidan boshlab ko'riladi, har biri hali band qilinmagan eng yangi nomzodni oladi (/clear'dan keyingi joriy sessiya, bir papkadagi ikki pane).
2. api/sessions.py: shu to'plamdagi sessiyalar past ro'yxatiga kirmaydi; resume ham 409 session_active beradi. Pane'siz tashqi active sessiyalar avvalgidek ko'rinadi (active=True).
3. Testlar: linking unit (bo'sh session_id, /clear, ikki pane, boshqa papka/agent/runner, pane'dan oldingi sessiya, started_at yo'q, tugagan pane) + API (yashirish, pane tugagach qaytishi va resume).
4. make check, build, backend restart, UI'da haqiqiy Claude sessiyasi bilan tekshirish.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Amalga oshirildi: linking.live_session_ids (ID'si noma'lum tirik pane uchun agent+realpath cwd+runner+started_at>=pane.started_at-5s bo'yicha eng yangi band qilinmagan sessiya), api/sessions.py past ro'yxatidan shu sessiyalarni chiqaradi va resume'da 409 session_active. Testlar: test_linking (3 ta yangi), tests/api/test_sessions.py::test_session_open_in_live_pane_is_not_past (pane tugagach qaytishi va 201 resume). make check: 459 + 61 o'tdi. Backend qayta ishga tushirildi. AC #4 kutilmoqda: brauzer kengaytmasi ulanmadi (3 urinish).

Haqiqiy tekshiruv (2026-09-15): agent-hub papkasida KanBot orqali claude pane a37929c5 ochildi (session_id bo'sh). /api/sessions: sessiya 7d391512 'past' da yo'q, resume 409 session_active. Pane kill qilingach 7d391512 'past' ga qaytdi (KanBot fayl yangi bo'lgani uchun hozircha active=True; resume esa unit/API testida 201). Codex resume pane (01a0a4a6) ham past'dan yashirildi. Frontend SessionsPanel data.past ni filtrsiz ko'rsatadi; brauzer kengaytmasi ulanmagani uchun vizual skrinshot olinmadi. Test pane ro'yxatdan olib tashlandi. make check: ruff, mypy, eslint, tsc, 459 pytest + 61 vitest o'tdi.

UI vizual tekshiruvi (Chrome, http://127.0.0.1:8700): claude pane c16a9115 (session_id bo'sh) «Jonli agentlar»da, sessiyasi a532a8e0 «O'tgan sessiyalar»da yo'q. Pane kill qilingach «Tugagan» (kod 143) bo'limiga o'tdi va sessiya o'tganlarga qaytdi; «Davom ettirish» KanBot active=True bo'lgan qisqa vaqt nofaol, ~2 daqiqalik avvalgi test sessiyasida faol. Test pane ro'yxatdan olib tashlandi.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Tirik pane'dagi sessiya endi «O'tgan sessiyalar»da takrorlanmaydi. linking.live_session_ids KanBot session_id bermaydigan qo'lda ochilgan pane'lar uchun sessiyani agent, realpath cwd, runner va started_at (pane'dan -5 s) bo'yicha topadi; har pane eng yangi band qilinmagan nomzodni oladi. /api/sessions ularni past'dan chiqaradi, resume 409 session_active qaytaradi. Testlar: test_linking (3 ta yangi) va API testi (yashirish, pane tugagach qaytishi, resume 201). Tekshiruv: make check o'tdi; haqiqiy claude pane bilan API'da yashirish, 409 va pane tugagach qaytish tasdiqlandi.
<!-- SECTION:FINAL_SUMMARY:END -->
