---
id: DRAFT-1
title: Codex holatini aniqlash (notify imkoniyati)
status: Draft
assignee:
  - '@claude'
created_date: '2026-09-15 14:46'
labels:
  - backend
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
14-oktabr 2026 dan keyin boshlanadi: Codex oylik limiti shu sanagacha tugagan. Codex hook yubormaydi, shuning uchun Agent Hub holatni ekrandan taxmin qiladi va Codex prompt kutayotganda ham «ishlamoqda ≈» ko'rinadi — blocked hisoblagichi va bildirishnomasi Codex uchun ishonchsiz (TASK-12 kuzatuvi). TASK-12 da Codex modelidan javob olinmagan, faqat trust dialogi va /status sinalgan. Codex'ning notify sozlamasi (tashqi buyruq chaqirish) holat manbai bo'la oladimi — tekshirilishi kerak.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Codex notify (yoki boshqa rasmiy) mexanizmi o'rganilgan va natija eslatmalarda yozilgan: qaysi hodisalar keladi, KanBot/Agent Hub'ga qanday yetkaziladi
- [ ] #2 Codex prompt yoki ruxsat kutayotganda UI'da «javob kutmoqda» ko'rinadi, ishlayotganda «ishlamoqda» (haqiqiy Codex sessiyasida tekshirilgan)
- [ ] #3 Codex modelidan haqiqiy javob olingan sessiya UI'dan ochilib, terminal va holat to'g'ri ishlashi tekshirilgan
<!-- AC:END -->
