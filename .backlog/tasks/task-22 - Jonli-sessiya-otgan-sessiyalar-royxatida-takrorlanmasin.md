---
id: TASK-22
title: Jonli sessiya o'tgan sessiyalar ro'yxatida takrorlanmasin
status: To Do
assignee:
  - '@claude'
created_date: '2026-09-15 14:46'
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
- [ ] #1 Jonli pane'ga mos keladigan sessiya o'tgan sessiyalar ro'yxatida ko'rsatilmaydi, jumladan pane session_id'si bo'sh bo'lgan holatda
- [ ] #2 Pane tugagach sessiya o'tganlar ro'yxatida qayta paydo bo'ladi va davom ettirish mumkin
- [ ] #3 Boshqa papkadagi yoki boshqa agentning sessiyasi noto'g'ri yashirilmaydi; holatlar testlar bilan yopilgan
- [ ] #4 Haqiqiy Claude sessiyasi bilan UI'da tekshirilgan
<!-- AC:END -->
