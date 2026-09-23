---
id: TASK-37
title: Claude va Codex limit foizini UI'da ko'rsatish
status: Done
assignee:
  - '@service@genso.uz'
created_date: '2026-09-23 16:08'
updated_date: '2026-09-23 16:45'
labels: []
dependencies: []
ordinal: 37000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Foydalanuvchi UI'da Claude Code va Codex CLI'ning joriy limit (rate limit) foizini ko'rishni so'radi — hozir buni bilish uchun terminal statusline'ga yoki alohida buyruqqa qarash kerak. Ikkala CLI ham bu ma'lumotni rasmiy tashqi API sifatida chiqarmaydi, shuning uchun manba tekshirildi: Codex har bir 'turn'dan keyin joriy sessiya rollout faylига ('~/.codex/sessions/**/rollout-*.jsonl', settings.transcript_roots['codex'] bilan bir xil) 'payload.rate_limits.{primary,secondary}.{used_percent,window_minutes,resets_at}' yozadi (window_minutes ~300 — 5 soatlik, ~10080 — 7 kunlik/haftalik; qaysi maydonda qaysi oyna kelishi barqaror emas, window_minutes qiymatiga qarab aniqlanadi). Claude Code esa bu ma'lumotni faqat interaktiv sessiya paytida statusLine buyrug'iga (foydalanuvchining '~/.claude/statusline.sh', settings.json'dagi statusLine) stdin JSON orqali beradi ('.rate_limits.five_hour/seven_day.{used_percentage,resets_at}'); boshqa hech qanday faylga yozilmaydi va CLI'da alohida 'usage' buyrug'i yo'q ('claude -p --output-format json' va 'claude auth status' bunday ma'lumot bermaydi, tekshirildi). Shu sababli Claude uchun statusline.sh'ga agent-hub o'qiy oladigan kichik keshga (masalan '~/.claude/agent-hub-rate-limits.json') oxirgi rate_limits'ni yozib turadigan qo'shimcha qo'shish kerak — bu loyiha tashqarisidagi shaxsiy dotfile, o'zgartirishdan oldin diff ko'rsatilib tasdiq so'raladi. Ma'lumot faqat tegishli CLI jonli/yaqinda ishlagan bo'lsa mavjud bo'ladi; UI buni hisobga olishi kerak.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 TopBar (yoki mos joy)da Claude'ning 5 soatlik va 7 kunlik limit foizi mavjud bo'lganda ko'rinadi, foizga qarab rangi o'zgaradi (yashil/sariq/qizil), tugash vaqti tooltip'da ko'rsatiladi
- [x] #2 TopBar'da Codex'ning limit foizi (5 soatlik va/yoki haftalik, mavjudiga qarab) xuddi shunday ko'rinadi
- [x] #3 Claude uchun kesh fayli yo'q/eskirgan bo'lsa UI xatosiz, tushunarli 'ma'lumot yo'q' holatini ko'rsatadi
- [x] #4 Codex uchun mos sessiya transkripti topilmasa yoki o'qib bo'lmasa UI xatosiz 'ma'lumot yo'q' holatini ko'rsatadi
- [x] #5 Backend hech qanday tashqi tarmoq so'rovi yubormaydi — faqat lokal fayllar o'qiladi
- [x] #6 Backend limit servisi (parsing, oyna aniqlash, freshness, xato holatlari) va frontend model funksiyalari uchun testlar qo'shilgan
- [x] #7 README'da yangi imkoniyat va Claude uchun statusline.sh talab qilinishi qisqa tasvirlangan
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Backend: src/agent_hub/services/limits.py — Window(used_percent, resets_at) va AgentLimits(agent, five_hour, weekly, updated_at, available) dataclass'lari + LimitsService. Claude: ~/.claude (yoki settings.claude_home) ichidagi kichik kesh faylini ('agent-hub-rate-limits.json') o'qiydi, fayl mtime orqali eskirganini belgilaydi, fayl yo'q bo'lsa available=False. Codex: hub orqali kelgan AgentSession ro'yxatidan agent=='codex' bo'lganlarning eng yangi mtime'lisini tanlaydi, services/transcripts.locate() bilan yo'lni tasdiqlaydi, faylni oxiridan o'qib oxirgi rate_limits(primary/secondary != null) qatorini topadi, window_minutes~300/~10080 orqali five_hour/weekly'ga ajratadi, qator timestamp'idan freshness oladi. Ikkalasi ham faqat lokal fayl o'qiydi, tarmoqqa chiqmaydi.

2. API: src/agent_hub/api/limits.py — GET /api/limits {claude:{...}, codex:{...}}; app.py'ga router qo'shiladi; api/deps.py Hub'ga self.limits = LimitsService(...) va kerakli yordamchi (masalan hub.codex_sessions()) qo'shiladi.

3. Frontend: api/types.ts (LimitWindow/AgentLimits/LimitsResponse), api/queries.ts (useLimits, ~15s poll), limits/model.ts (foiz->rang/tone sof funksiyalari + test), yangi kichik komponent (masalan LimitBadges.tsx) TopBar'ga UpdateButtons yonida; i18n uz.ts (va ru.ts placeholder) matnlari.

4. ~/.claude/statusline.sh ga qo'shimcha: hisoblangan rate_limits obyektini ~/.claude/agent-hub-rate-limits.json ga yozib turadi. LOYIHA TASHQARISIDAGI SHAXSIY DOTFILE — o'zgartirishdan oldin aniq diff ko'rsatilib, alohida tasdiq so'raladi.

5. README.md: yangi UI elementi va Claude uchun statusline.sh talabi qisqa tasvirlanadi.

6. Testlar: tests/test_limits.py (parsing, oyna aniqlash, freshness, yo'q-fayl holatlari) va web/src/limits/model.test.ts; mavjud test to'plami (make test / npm test) ishga tushirilib tekshiriladi.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Backend tayyor va test qilindi: services/limits.py, api/limits.py (GET /api/limits), app.py/deps.py'ga ulandi. tests/test_limits.py (15 ta) va tests/api/test_limits.py (3 ta) qo'shildi — barchasi + mavjud 584 ta test o'tdi. Foydalanuvchi 'har 5 sec yangilanib turishi kerak' dedi — frontend useLimits() refetchInterval=5000 bilan yoziladi (rejadagi ~15s emas).

Yakuniy tekshiruv: alohida AGENT_HUB_PORT=8799 misolida (asosiy 8700-portdagi jonli instansiyaga tegmasdan) GET /api/limits haqiqiy jonli ma'lumot bilan sinaldi — natija: claude.available=true, five_hour.used_percent=95.0, weekly.used_percent=83.0 (ikkalasi ham >=75% => qizil rang chegarasi), codex.available=false (mos sessiya topilmagani uchun, xatosiz). Bu AC#1/#2 rang mantig'ini va AC#3/#4 'ma'lumot yo'q' holatini haqiqiy ma'lumot bilan tasdiqladi. Brauzerda vizual skrinshot orqali tekshirish Claude-in-Chrome kengaytmasining 127.0.0.1 (loopback) manzillarga yeta olmasligi (xavfsizlik/SSRF cheklovi bo'lsa kerak) sababli bajarilmadi — curl bilan to'g'ridan-to'g'ri so'rov muvaffaqiyatli, lekin brauzer navigate/fetch orqali doim {ok:false,description:'not found'} qaytardi; bu vosita cheklovi, backendga aloqasi yo'q. Shu sababli UI render mantig'i (rang/tooltip/badge) web/src/limits/model.test.ts (10+ test) va komponent kodini ko'rib chiqish orqali tasdiqlandi, real piksel skrinshot bilan emas. README.md ga 'Limit foizi' bo'limi qo'shildi (AC#7). Yakuniy tekshiruv: backend 584 test (ruff/mypy toza), frontend 107 test + typecheck/lint/build toza.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
TopBar'ga Claude Code va Codex CLI uchun rate-limit foizi badge'lari qo'shildi (5s/7k, rangi 50%/75% chegaralarida sariq/qizilga o'zgaradi, tooltip'da tiklanish vaqti). Backend: services/limits.py + api/limits.py (GET /api/limits) — Claude uchun ~/.claude/agent-hub-rate-limits.json keshini, Codex uchun eng so'nggi rollout-*.jsonl sessiyasini o'qiydi, faqat lokal fayllar, tarmoq so'rovi yo'q. ~/.claude/statusline.sh ga (foydalanuvchi tasdig'i bilan) keshni yozib turadigan qo'shimcha qo'shildi. Frontend har 5 soniyada so'raydi (useLimits, foydalanuvchi so'ragan tezlik). Tekshirildi: backend 584 test (yangi 18 tasi shu vazifa uchun) + ruff/mypy toza; frontend 107 test (yangi limits/model.test.ts) + typecheck/lint/build toza; alohida test-instansiyada (8799-port) real jonli ma'lumot bilan GET /api/limits qo'lda tasdiqlandi (Claude 95%/83% qizil rang, Codex 'ma'lumot yo'q'). Brauzer orqali piksel-darajasidagi vizual tekshiruv Claude-in-Chrome kengaytmasi 127.0.0.1'ga yeta olmagani sababli imkonsiz bo'ldi (vosita cheklovi) — bu implementation notes'da batafsil yozilgan. README.md'ga 'Limit foizi' bo'limi qo'shildi.
<!-- SECTION:FINAL_SUMMARY:END -->
