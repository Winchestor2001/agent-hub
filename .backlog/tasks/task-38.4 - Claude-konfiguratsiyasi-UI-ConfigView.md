---
id: TASK-38.4
title: 'Claude konfiguratsiyasi: UI (ConfigView)'
status: Done
assignee:
  - '@claude'
created_date: '2026-09-24 16:38'
updated_date: '2026-10-07 11:40'
labels: []
dependencies:
  - TASK-38.2
  - TASK-38.3
parent_task_id: TASK-38
ordinal: 42000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Backend va shablonlar tayyor bo'lgach foydalanuvchi butun Claude Code tuzilmasini (rasmdagi ro'yxat) brauzerdan sozlashi kerak: default (global) darajada va ixtiyoriy ravishda har bir loyihada alohida, bitta yoki bir nechta loyihaga birdaniga.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 TopBar'dagi Konfiguratsiya tugmasi va loyiha qatoridagi belgi butun ekranli ConfigView ochadi; qamrov (Global yoki loyiha) tanlanadi va ikkalasi ixtiyoriy
- [x] #2 Har tur uchun element ro'yxati (qidiruv bilan, 90 dan ortiq skill uchun ham qulay), muharrir, yaratish va o'chirish ishlaydi
- [x] #3 Saqlashdan oldin o'zgarishlar diff ko'rinishida ko'rsatiladi; 409 bo'lsa foydalanuvchiga tushunarli ogohlantirish chiqadi va qayta yuklash mumkin
- [x] #4 Shablondan yaratish, o'z fayl/matnini yuklash yoki qo'yish va qo'llanmani ko'rish ishlaydi
- [x] #5 Qo'llash: bitta kontent global va tanlangan loyihalarga yoziladi, natija har qamrov uchun ko'rsatiladi
- [x] #6 Global skill loyiha skilini yopishi va CLAUDE.local.md ni gitignore'ga qo'shish kerakligi haqida ogohlantirishlar ko'rinadi
- [x] #7 uz+ru i18n to'liq, yangi npm bog'liqlik qo'shilmagan; vitest, eslint, tsc yashil
- [x] #8 README'da konfiguratsiya bo'limi bor; make check yashil; brauzerda qo'lda tekshirilgan
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. api/types.ts + queries.ts: /api/claude-config/* uchun turlar va hook'lar (scopes, items, file, templates, guides; write/delete/apply mutatsiyalari, invalidatsiya).
2. web/src/config/: diff.ts (LCS qator diff), markdown.tsx (kichik xavfsiz renderer — HTML'siz, React elementlar), model.ts (qidiruv filtri, tur/qamrov mosligi, yangi nom taklifi) + vitest.
3. components/ConfigView.tsx: to'liq ekran; qamrov tanlash (Global/loyiha papkalari), turlar ro'yxati, qidiruvli elementlar ro'yxati, textarea muharrir; saqlashdan oldin diff dialog; 409 da ogohlantirish + qayta yuklash; o'chirish tasdiq bilan; shadow va local_not_ignored ogohlantirishlari.
4. Yangi element: shablondan / fayl yuklash / matn qo'yish; qo'llanma paneli (markdown).
5. Apply dialog: global + tanlangan loyihalar, overwrite, har qamrov natijasi.
6. App: TopBar «Konfiguratsiya» tugmasi va loyiha qatorida ⚙ — ConfigView asosiy panellar o'rnida.
7. uz/ru i18n, README bo'limi, make check, Playwright bilan brauzer tekshiruvi.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Amalga oshirish:
- Markdown: parser web/src/config/markdown.ts, komponent components/Markdown.tsx (react-refresh qoidasi tufayli ajratildi); HTML ishlatilmaydi, havolalar faqat http(s).
- Diff: config/diff.ts — umumiy prefiks/suffiks kesilib LCS, 4M katakdan katta bo'lsa to'liq almashtirish; 3 qator kontekst.
- Saqlanmagan qoralama bor paytda qamrov/tur/element almashtirish yoki yopish — tasdiq so'raladi.
- Apply dialog holati ConfigEditor'da: joriy qamrov ham yozilib forma qayta yuklansa ham natija ko'rinib turadi.
- Tor oyna: topbar .app grid ustunini 1170px gacha cho'zib yuborardi (avvaldan bor muammo) — .app grid-template-columns: minmax(0,1fr), topbar o'zi aylantiriladi (overflow-x, bolalar flex-shrink: 0). 860px da doska ham, konfiguratsiya ham sahifaga sig'adi.

Tekshiruv:
- make check yashil: pytest 736 passed, vitest 145 passed (19 fayl), eslint --max-warnings 0, tsc.
- Playwright (alohida QA backend :8711, CLAUDE_CONFIG_DIR va AGENT_HUB_CONFIG_DIR scratchpad'da, haqiqiy ~/.claude tegilmadi), 28/28: Konfiguratsiya tugmasi va loyiha ⚙ ochadi; 95 skill, qidiruv skill-9 → 7 ta; diff → Diskka yozish → fayl va zaxira nusxa; diskdagi tashqi o'zgarishda 409 ogohlantirishi, fayl ustiga yozilmadi, Qayta yuklash diskdagi matnni ochdi; saqlanmagan o'zgarish tasdig'i; shablondan qa-new + Qo'llash Global+QA Lifecycle → ikkalasi «yaratildi»; qo'llanma paneli; loyihada «yopilgan» va global'da «ustun» ogohlantirishlari; CLAUDE.local.md gitignore ogohlantirishi; fayl yuklash (Code Style.md → code-style) → yaratish → o'chirish; ruscha sarlavha; sahifa xatolari yo'q.
- Skrinshotlar 1440px va 860px da ko'rib chiqildi.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Brauzerda Claude Code konfiguratsiyasini boshqaruvchi ConfigView qo'shildi. U TopBar'dagi «Konfiguratsiya» tugmasi va loyiha qatoridagi ⚙ orqali ochiladi va asosiy panellar o'rnida ko'rinadi. Imkoniyatlar: Global va loyiha qamrovlari; har tur bo'yicha qidiruvli ro'yxat va muharrir; saqlashdan oldin diff; 409 konfliktda ogohlantirish, qoralamani nusxalash va qayta yuklash; tasdiq bilan o'chirish; shablon, fayl yuklash yoki matn qo'yish; o'zbekcha qo'llanma paneli; bir nechta qamrovga qo'llash (har qamrov natijasi alohida); shadow va CLAUDE.local.md gitignore ogohlantirishlari. uz+ru i18n, README bo'limi qo'shildi, yangi npm bog'liqlik yo'q. Tor oynada topbar sahifani kengaytirib yuborishi ham tuzatildi. Tekshiruv: make check yashil (pytest 736, vitest 145, eslint, tsc) va izolyatsiyalangan QA backend'da Playwright stsenariysi 28/28.
<!-- SECTION:FINAL_SUMMARY:END -->
