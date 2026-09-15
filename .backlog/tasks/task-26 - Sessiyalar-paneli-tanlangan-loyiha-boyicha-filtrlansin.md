---
id: TASK-26
title: Sessiyalar paneli tanlangan loyiha bo'yicha filtrlansin
status: Done
assignee:
  - '@claude'
created_date: '2026-09-15 18:29'
updated_date: '2026-09-15 18:37'
labels:
  - client
dependencies: []
ordinal: 26000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Sessiyalar panelidagi 'Javob kutmoqda', 'Jonli agentlar' va 'Tugagan' bo'limlari hozir qaysi loyiha tanlanganidan qat'i nazar barcha loyihalarning ochiq sessiyalarini ko'rsatadi (faqat 'O'tgan sessiyalar' loyiha bo'yicha). Loyihalar ko'paygach ro'yxat aralashib ketadi va tanlangan loyihada kim ishlayotganini ajratish qiyin. Foydalanuvchi talabi (2026-09-15): loyiha tanlanganda faqat shu loyihaga oid sessiyalar ko'rinsin. Sessiya loyihaga cwd bo'yicha bog'lanadi (pane.project_id); loyihadan tashqaridagi sessiyalar ham bor va ular butunlay ko'rinmay qolmasligi kerak. Blocked bildirishnomalari va sarlavhadagi hisoblagich esa barcha loyihalar uchun ishlashi kerak — boshqa loyihadagi agent javob kutayotganini bilish muhim.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Loyiha tanlanganda 'Javob kutmoqda', 'Jonli agentlar' va 'Tugagan' bo'limlarida faqat shu loyiha sessiyalari ko'rinadi, hisoblagichlar ham shunga mos
- [x] #2 Boshqa loyihalardagi va loyihadan tashqaridagi jonli sessiyalar yo'qolib ketmaydi: ularning soni (javob kutayotganlari alohida) ko'rinadi va bir bosishda barcha sessiyalarni ko'rsatishga hamda qaytishga o'tish mumkin
- [x] #3 Alt+Shift+↑/↓ faqat panelda ko'rinayotgan sessiyalar orasida o'tadi
- [x] #4 Blocked bildirishnomasi va sarlavhadagi hisoblagich barcha loyihalar bo'yicha ishlaydi; bildirishnoma bosilganda sessiya loyihasi tanlanadi va terminali ochiladi
- [x] #5 Frontend testlari; uz/ru matnlar; README yangilangan
- [x] #6 Haqiqiy UI'da bir necha loyihadagi sessiyalar bilan tekshirilgan
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Topilmalar: SessionsPanel useLiveSessions ro'yxatini (live + finished) filtrsiz ko'rsatadi; App navigationOrder/useSessionShortcuts va useBlockedAlerts ham barcha pane'lar bilan ishlaydi; loyiha har doim tanlangan (selectedId yoki birinchi loyiha), loyiha bo'lmasa null. Pane loyihasi backend'dan pane.project_id.
1. model.ts: sof splitByProject(panes, projectId) -> {mine, others} (projectId null bo'lsa hammasi mine) + testlar.
2. App: showAllSessions holati; ko'rinadigan jonli pane'lar (tanlangan loyiha yoki hammasi) navigationOrder'ga beriladi — Alt+Shift+↑/↓ faqat ular orasida. useBlockedAlerts barcha pane'lar bilan qoladi (sarlavha hisoblagichi global); bildirishnoma bosilganda pane loyihasi tanlanadi (boshqa bo'lsa, ochiq vazifa yopiladi) va terminal ochiladi.
3. SessionsPanel: showAll/onToggleShowAll prop; blocked/jonli/tugagan bo'limlari filtrlangan ro'yxatdan; Jonli agentlar ostida 'Boshqa loyihalarda yana N ta sessiya · M tasi javob kutmoqda · Hammasini ko'rsatish' (M>0 bo'lsa qizil), hammasi rejimida 'Barcha loyihalar · Faqat <loyiha>'. Loyihadan tashqaridagi sessiyalar 'boshqa' hisobida.
4. uz/ru kalitlar, CSS, README (Sessiyalar paneli filtri, shortcut jadvali).
5. make check, make build; UI: 8711 test instansiyada soxta KanBot'ga ikki loyiha va loyihasiz pane'lar qo'shib Playwright bilan tekshirish (filtr, hisoblagich, toggle, shortcut, blocked hisoblagich).
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Qilindi: model.splitByProject (+2 vitest); App — showAllSessions holati, Alt+Shift+↑/↓ tartibi faqat ko'rinayotgan pane'lardan, useBlockedAlerts barcha pane'lar bilan, bildirishnoma bosilganda pane loyihasi tanlanadi (ochiq vazifa yopiladi) va terminal ochiladi; SessionsPanel — blocked/jonli/tugagan filtrlangan, ScopeHint ('Boshqa loyihalarda yana N ta sessiya', javob kutayotganlari qizil, Hammasini ko'rsatish / Faqat <loyiha>); uz/ru, CSS, README. make check: 477 pytest, 69 vitest, lint/tiplar toza; make build.
UI tekshiruvi (Playwright headless Chromium, 8711 test instansiya, soxta KanBot: demo-app 2 jonli + 1 tugagan, other-app 2 jonli + 1 tugagan, loyihasiz 1): demo-app'da faqat o'z sessiyalari va hisoblagichlar 1/1/1, 'yana 3 ta sessiya · 1 tasi javob kutmoqda', sarlavha (2); Alt+Shift+↓ faqat demo-app'ning 2 sessiyasi bo'ylab aylandi; Hammasini ko'rsatish 2/3/2 va loyihasiz sessiya ko'rindi, shortcut 5 ta bo'ylab; Faqat demo-app qaytardi; other-app tanlanganda uning sessiyalari; demo-app tanlanganda other-app'da yangi blocked — bildirishnoma chiqdi, sarlavha (3), bosilganda other-app tanlandi va terminal ochildi; ru matnlar.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Sessiyalar paneli (Javob kutmoqda, Jonli agentlar, Tugagan) endi tanlangan loyiha bo'yicha filtrlanadi; boshqa loyihalardagi va loyihadan tashqaridagi jonli sessiyalar soni (javob kutayotganlari alohida) ko'rsatiladi va 'Hammasini ko'rsatish' / 'Faqat <loyiha>' bilan almashtiriladi. Alt+Shift+↑/↓ faqat ko'rinayotgan sessiyalar bo'ylab; blocked bildirishnomasi va sarlavha hisoblagichi global, bildirishnoma bosilganda sessiya loyihasi tanlanadi. uz/ru, README. Tekshiruv: make check (477 pytest, 69 vitest) va Playwright UI skripti ikki loyiha + loyihasiz soxta pane'larda.
<!-- SECTION:FINAL_SUMMARY:END -->
