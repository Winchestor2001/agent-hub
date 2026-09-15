---
id: TASK-19
title: Bildirishnomalar va qulayliklar
status: Done
assignee:
  - '@claude'
created_date: '2026-09-15 07:27'
updated_date: '2026-09-15 12:27'
labels:
  - client
milestone: m-2
dependencies:
  - TASK-16
ordinal: 19000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Blocked holatida xabar berish va navigatsiya qulayliklari.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Blocked holatida brauzer bildirishnomasi va tab sarlavhasida hisoblagich
- [x] #2 Sessiyalar orasida klaviatura bilan o'tish; tugagan pane'ni ro'yxatdan olib tashlash
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Backend /api/sessions: tirik pane'lar 'live' da qoladi; tugagan (alive=false) pane'lar yangi 'finished' ro'yxatida (loyiha filtri, vazifa bog'lash, ended_at bo'yicha yangi birinchi). KanBot o'zi ularni ~2 soat saqlaydi.
2. DELETE /api/sessions/{pane_id}: pane tirik bo'lsa 409 pane_alive (KanBot remove tirik pane'ni SIGKILL qiladi — bu yo'l bilan agent o'ldirilmaydi), aks holda KanBot DELETE /api/panes/{id}. SessionEnd hook'dan kelgan done+alive pane jonli ro'yxatda qoladi.
3. Frontend: useLiveSessions {live, finished}; SessionsPanel da 'Tugagan' bo'limi (terminalni ochish, ×, hammasini tozalash); olib tashlangan pane terminali ochiq bo'lsa yopiladi.
4. Blocked xabarlari: sof funksiyalar (sarlavha hisoblagichi, yangi blocked pane'lar) + useBlockedAlerts: document.title '(N) Agent Hub'; pane yangi blocked bo'lganda (birinchi yuklanishda emas) tab fokusda bo'lmasa Notification (tag = pane id, bosilganda tab fokus va terminal ochiladi). TopBar da ruxsat so'rash tugmasi (permission=default).
5. Klaviatura: Alt+Shift+↓/↑ — keyingi/oldingi jonli sessiya terminali (ko'rinish tartibida, aylanma; terminal fokusda ham ishlaydi, oddiy input'larda emas); sessiyalar ro'yxatida ↑/↓/Home/End fokusni ko'chiradi. Panelda qisqa ko'rsatma.
6. Testlar: pytest (finished, DELETE), vitest (sarlavha, yangi blocked, navigatsiya); make check; UI da qo'lda tekshiruv.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Rejadan og'ishlar va topilmalar:
- Shortcut tartibi ko'rinish tartibi emas, barqaror tartib (blocked, keyin started_at). Sabab: ro'yxat oxirgi chiqish bo'yicha saralanadi, terminal ulanishi esa pane'da chiqish hosil qiladi. Natijada har bosishda pane'lar joy almashib, 'keyingisi' sakrab ketardi (UI'da ko'rildi).
- Olib tashlashdan keyin terminalni yopish mutateAsync orqali qilinadi. Oxirgi pane olingach 'Tugagan' bo'limi unmount bo'ladi va mutate({onSuccess}) chaqirilmay qolardi (UI'da topildi va tuzatildi).
- useLiveSessions refetchIntervalInBackground=true: blocked xabari boshqa tabda turganda kerak, SSE uzilsa ham polling to'xtamasin.
- DELETE da 404 pane_not_found xato hisoblanmaydi (KanBot allaqachon tozalagan bo'lishi mumkin).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Blocked xabarlari, sessiyalar orasida klaviatura bilan o'tish va tugagan pane'larni tozalash qo'shildi.

Backend:
- /api/sessions endi 'finished' ro'yxatini qaytaradi (alive=false, ended_at bo'yicha yangisi oldin).
- DELETE /api/sessions/{pane_id}: tirik pane'ga 409 pane_alive, chunki KanBot remove tirik pane'ni SIGKILL qiladi. Noto'g'ri ID 422, yo'q pane 404, KanBot o'chiq bo'lsa 503.

Frontend:
- sessions/alerts.ts: tab sarlavhasi '(N) Agent Hub'. Pane yangi blocked bo'lsa (birinchi yuklanishda emas) va tab fokusda bo'lmasa brauzer Notification chiqadi; tag pane bo'yicha, bosilganda terminal ochiladi. TopBar'da ruxsat tugmasi, rad etilgan bo'lsa ko'rsatma.
- sessions/navigation.ts: Alt+Shift+↓/↑ capture listener. Terminal fokusda ham ishlaydi, oddiy input'larda va ochiq dialogda ishlamaydi. Tartibi barqaror va aylanma. Ro'yxatda ↑/↓/Home/End fokusni ko'chiradi; panelda ko'rsatma bor.
- SessionsPanel: 'Tugagan' bo'limi (kod, vaqt, terminalni ochish, ×, Tozalash). Olib tashlangan pane terminali ochiq bo'lsa yopiladi.

Tekshiruv:
- make check: pytest 452, vitest 55, ruff/mypy/eslint/tsc toza. make build bajarildi, backend qayta ishga tushirildi.
- UI'da haqiqiy KanBot bilan tekshirildi: AskUserQuestion bilan blocked holati chiqarildi, sarlavha '(1) Agent Hub' bo'ldi va panelda 'Javob kutmoqda' ko'rindi. Alt+Shift+↓/↑ xterm fokusda bo'lganida ikki pane orasida aylandi (ID bo'yicha tekshirildi). ↓/Home fokusni ko'chirdi. /exit'dan keyin pane 'Tugagan'ga o'tdi; × va Tozalash ro'yxatni bo'shatdi va ochiq terminalni yopdi.
- Tekshirilmagan: OS bildirishnoma banneri. Brauzer ruxsati 'default' holatda qoldi, ruxsat berish foydalanuvchining qarori; kod yo'li va shartlari unit testlar bilan yopilgan.
<!-- SECTION:FINAL_SUMMARY:END -->
