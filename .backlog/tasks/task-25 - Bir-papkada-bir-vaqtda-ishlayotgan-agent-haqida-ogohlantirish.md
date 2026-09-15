---
id: TASK-25
title: Bir papkada bir vaqtda ishlayotgan agent haqida ogohlantirish
status: To Do
assignee: []
created_date: '2026-09-15 17:32'
labels:
  - backend
  - client
dependencies: []
ordinal: 25000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bitta repo papkasida bir nechta agent bir vaqtda kod yozsa, ular bir-biriga xalal beradi: bir faylni ikkalasi tahrirlaydi, git add -A boshqasining chala ishini commit'ga qo'shadi, chala kod boshqa agentning testini yiqitadi, build/port to'qnashadi. Agent Hub sessiyalarni ajratmaydi (hammasi loyiha papkasida ochiladi, worktree yo'q). Foydalanuvchi qarori (2026-09-15): 'bitta papkada navbat bilan' ishlash — bir nechta vazifa sessiyasi ochilib reja yozadi va kutadi (shablon promptida tasdiqsiz kod yozma deyilgan), foydalanuvchi bir vaqtda faqat bittasiga ruxsat beradi. Hub buni eslatib turishi kerak: faqat ogohlantirish, hech narsani bloklamaydi. Xavf repo papkasiga bog'liq — bir loyihaning turli repo'larida ishlayotgan agentlar bir-biriga xalal bermaydi.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Yangi sessiya oynasida, tanlangan papkada boshqa jonli sessiya hozir ishlayotgan (working) bo'lsa, u sessiya nomi/vazifasi bilan ogohlantirish ko'rinadi; sessiyani baribir boshlash mumkin
- [ ] #2 Sessiya terminali ochilganda, shu papkadagi boshqa sessiya ishlayotgan bo'lsa, terminal ustida ogohlantirish chiqadi va u sessiya ishlashni to'xtatganda yo'qoladi
- [ ] #3 Boshqa papka/repo'dagi, tugagan yoki kutayotgan (blocked/idle) sessiyalar ogohlantirish chiqarmaydi; holat ekrandan taxminiy (≈) aniqlangan bo'lsa ham ishlaydi
- [ ] #4 Ogohlantirish hech qanday amalni bloklamaydi va KanBot'ga qo'shimcha so'rov yubormaydi (mavjud jonli holat ma'lumotidan hisoblanadi)
- [ ] #5 Backend/frontend testlari; uz/ru matnlar; README'da 'bitta papkada navbat bilan' ish tartibi va ogohlantirish tushuntirilgan
- [ ] #6 Haqiqiy UI'da ikki sessiya bilan tekshirilgan
<!-- AC:END -->
