---
id: TASK-56
title: 'AI Island: Skills ro‘yxatini skill bo‘yicha guruhlash va yangi skill yaratish'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-12 06:58'
updated_date: '2026-10-12 07:21'
labels: []
dependencies: []
ordinal: 79000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
~/.claude/skills ichida 800 dan ortiq fayl bor, lekin haqiqiy skill (SKILL.md) atigi ~32 ta; qolganlari ularning references/scripts fayllari. Skills oynasi hammasini bitta tekis ro‘yxatda ko‘rsatgani uchun asosiy skill’larni topish va ularga qaysi fayllar tegishli ekanini ko‘rish qiyin. Bundan tashqari, "+" tugmasi skills ildiziga oddiy new-item.md yaratadi, Claude esa faqat <nom>/SKILL.md tuzilmasini skill sifatida taniydi — foydalanuvchi o‘z backend skill’ini qo‘shmoqchi.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Skills (Claude va Codex) ro‘yxatida har bir SKILL.md papkasi bitta qator bo‘lib chiqadi, unga tegishli fayllar ochilmaguncha yashirin turadi
- [x] #2 Skill qatorini ochganda (disclosure) unga ulangan fayllar skill papkasiga nisbatan yo‘l bilan ko‘rinadi; skill qatorini tanlash SKILL.md ni editorda ochadi
- [x] #3 Qidiruv skill nomi va ichki fayllar bo‘yicha ishlaydi; mos fayli bor skill avtomatik ochilib, faqat mos fayllar ko‘rsatiladi
- [ ] #4 Skills kartasi va ro‘yxat sarlavhasi skill sonini va fayl sonini alohida ko‘rsatadi
- [ ] #5 Skills dagi "+" nom kiritilganda <nom>/SKILL.md ni frontmatter shabloni bilan yaratadi; <skill>/references/x.md kabi ichki yo‘l ham qabul qilinadi, .. va absolyut yo‘llar rad etiladi
- [x] #6 Boshqa kategoriyalar (Agents, Commands, Hooks, Settings) avvalgidek tekis ro‘yxat
- [ ] #7 Guruhlash mantig‘i uchun unit testlar bor; swift test va --settings-regression-report o‘tadi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ClaudeSessions modulida SkillTree (sof mantiq): fayllarni SKILL.md papkalari bo‘yicha guruhlash (eng chuqur ildiz yutadi), qolganlari loose; qidiruv filtri; yangi fayl yo‘lini tekshirish (segmentlar, .. yo‘q). Unit testlar.
2. main.swift: Skills kategoriyasida NSTableView o‘rniga NSOutlineView (u NSTableView subclass, mavjud API saqlanadi): skill tugunlari + bolalar; expanded holat saqlanadi; skill qatori SKILL.md ni ochadi.
3. Qidiruv: mos fayli bor skill avtomatik ochiladi.
4. Karta va sarlavhada "N skills · M files".
5. "+" Skills da: nom → <nom>/SKILL.md shablon bilan; ichki yo‘l qabul qilinadi.
6. Settings regression testini yangi qator modeliga moslash, Uzbek tarjimalar qo‘shish.
7. swift test + build + --settings-regression-report.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
SkillTree (ClaudeSessions) + 6 unit test qo‘shildi va o‘tdi. main.swift: Skills ro‘yxati skill bo‘yicha guruhlangan (chevron, ←/→, double-click), qidiruv mos skillni ochadi, karta/sarlavhada skill+fayl soni, "+" <nom>/SKILL.md shablon bilan yoki ichki yo‘l yaratadi. Debug build o‘tdi. To‘liq swift test bir marta 66/1 failure bilan tugadi (qaysi test ekanini ko‘rib bo‘lmadi: aynan o‘sha paytda Xcode 27.0 yangilandi va endi litsenziya qabul qilinmaguncha swift build/test ishlamaydi). Qayta tekshiruv va --settings-regression-report kutilmoqda.

Tekshiruv (Xcode litsenziyasi qabul qilingach): swift test — 66/66 o‘tdi (oldingi 1 failure Xcode yangilanishi paytiga to‘g‘ri kelgan). --settings-regression-report (debug binary): "PASS skills: Claude::Skills — 32 skills, 803 files, hyperframes expands to 25" va Codex 10 skills/361 files; qidiruv, layout/selection barcha kategoriyalarda PASS. Command-W tekshiruvi beqaror va o‘zgarishsiz main da ham yiqiladi ("Command-W did not close Settings") — bu vazifaga aloqasiz. Hali qo‘lda tekshirilmagan: karta badge matni (AC4) va "+" orqali skill yaratish modal oqimi (AC5; newItemPath/template unit-testlangan). Alohida topilgan muammo: scripts/build-ai-island-app.sh SwiftPM resurs bundle (AIIslandApp_AIIslandApp.bundle) ni .app ichiga ko‘chirmaydi, shuning uchun dist ilovasi ishga tushganda Bundle.module da crash bo‘ladi.
<!-- SECTION:NOTES:END -->
