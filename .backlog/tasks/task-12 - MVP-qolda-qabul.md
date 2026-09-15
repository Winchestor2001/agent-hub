---
id: TASK-12
title: MVP qo'lda qabul
status: Done
assignee:
  - '@claude'
created_date: '2026-09-15 07:27'
updated_date: '2026-09-15 10:44'
labels: []
milestone: m-0
dependencies:
  - TASK-9
  - TASK-11
ordinal: 12000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Haqiqiy KanBot (dev-rejim) va Leveling bilan end-to-end tekshiruv.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 UI'dan vazifaga bog'langan Claude sessiyasi: yozish ishlaydi, working → blocked (haqiqiy ruxsat so'rovi) → idle ko'rinadi
- [x] #2 Codex sessiyasi UI'dan interaktiv ishlaydi
- [x] #3 UI'dagi status o'zgarishi Leveling .backlog/ da ko'rinadi; hisoblagichlar to'g'ri
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Haqiqiy dev muhit: make dev-kanbot (8787, ~/.kanbot), make dev-runner (SAFE), make dev (Agent Hub 8700, ~/.config/agent-hub registri).
2. Leveling'da UI'dan vaqtinchalik sinov vazifasi (foydalanuvchi ruxsati bilan); oxirida backlog CLI bilan arxivlanadi.
3. AC#1: vazifadan Claude sessiyasi (zararsiz prompt: 'date' buyrug'ini ishga tushirish, fayl o'zgartirmaslik) — terminalda yozish, working → blocked (Bash ruxsati) → ruxsat berish → idle UI'da kuzatiladi.
4. AC#2: Codex sessiyasi UI'dan, terminal orqali qo'shimcha xabar yozib javob olish.
5. AC#3: UI'dan status To Do → In Progress → Done; Leveling .backlog/ faylida va hisoblagichlarda tekshirish.
6. Sessiyalarni tugatish, sinov vazifasini arxivlash, serverlarni to'xtatish; natijalarni notes'ga yozish.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Qabul (2026-09-15, haqiqiy dev muhit: make dev-kanbot 8787, dev-runner SAFE, make dev 8700; Chrome):
- Tuzatildi: banner bo'lmaganda .panels grid'ning 2-(auto) qatoriga tushib, balandligi ~190px bo'lib qolardi → .panels { grid-row: -2 }.
- Leveling'da UI'dan vaqtinchalik TASK-001 'Agent Hub qabul sinovi' yaratildi (foydalanuvchi ruxsati bilan); oxirida CLI bilan To Do → archive (backlog Done vazifani arxivlamaydi). Leveling'dagi config.yml o'zgarishi va uv.lock sinovdan oldin ham bor edi.
- AC#1: vazifadan Claude sessiyasi (sarlavhada TASK-001, doska kartasida badge). Claude'da auto mode yoqilgan va date read-only bo'lgani uchun ruxsat so'ralmadi; sessiya ichida Shift+Tab bilan manual mode. 'mkdir -p /tmp/agent-hub-qabul-sinovi' so'rovi → haqiqiy Bash ruxsat dialogi, UI: ishlamoqda → javob kutmoqda (loyiha kartasida '1 blocked') → Esc bilan rad → bo'sh (hook, approximate=false). Papka yaratilmadi. Ctrl-C ×2 bilan Claude chiqdi.
- AC#2: Codex UI'dan ochildi; trust dialogi Enter tugmasi bilan tasdiqlandi (foydalanuvchi ruxsati bilan ~/.codex/config.toml ga leveling-backend trusted yozuvi qo'shildi), /status yozildi va javob ekranda ko'rindi, Ctrl-C bilan chiqdi. Cheklov: Codex hisobida oylik limit tugagan (14-oktabrgacha), shuning uchun model javobi olinmadi; reset'lar ishlatilmadi.
- AC#3: drawer'dan status To Do → In Progress → Done; har birida Leveling .backlog/tasks/task-001 faylidagi status va 'backlog task list' mos keldi; loyiha kartasi va ustun hisoblagichlari 1/0/0 → 0/1/0 → 0/0/1.
- Kuzatuvlar (tuzatilmadi): (1) tugagan pane jonli ro'yxatdan chiqqach terminal sarlavhasida faqat pane id qoladi, 'tugagan' belgisi ko'rinmaydi; (2) jonli Claude sessiyasi o'tgan sessiyalar ro'yxatida ham ko'rinadi (KanBot session_id bo'sh); (3) Codex holati hook'siz — prompt kutayotganda ham 'ishlamoqda ≈'; (4) Chrome oynasi fonda bo'lsa polling pauza (dizayn bo'yicha); (5) Leveling bekloqida backlog CLI arxivdagi task-001 bilan bir xil ID berdi.
- make check: ruff, mypy 48 fayl, pytest 405 passed, eslint, tsc, vitest 40 passed; make build OK.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
MVP haqiqiy KanBot (dev, SAFE runner) va Leveling bilan qo'lda qabul qilindi: vazifaga bog'langan Claude sessiyasida terminal orqali yozish va haqiqiy ruxsat so'rovi bilan working → blocked → idle; Codex sessiyasi UI terminalida interaktiv (trust dialogi, /status, chiqish — model limiti tugagani uchun model javobisiz); UI'dan status o'zgarishlari Leveling .backlog/ faylida va hisoblagichlarda to'g'ri. Sinov davomida topilgan layout xatosi (banner yo'q bo'lsa panellar siqilishi) tuzatildi. Vaqtinchalik vazifa arxivlandi; make check va build o'tdi.
<!-- SECTION:FINAL_SUMMARY:END -->
