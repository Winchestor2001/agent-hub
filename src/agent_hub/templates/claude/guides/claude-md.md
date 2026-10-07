# CLAUDE.md va CLAUDE.local.md

`CLAUDE.md` — Claude har sessiya boshida o'qiydigan yo'riqnoma: loyiha nima, qanday buyruqlar, qanday qoidalar.

- **Global** `~/.claude/CLAUDE.md` — barcha loyihalarga umumiy odatlaringiz (til, uslub).
- **Loyiha** `CLAUDE.md` — jamoa bilan bo'lishiladigan loyiha qoidalari (git'ga qo'shiladi).
- **Shaxsiy** `CLAUDE.local.md` — faqat sizga tegishli loyiha eslatmalari (mahalliy URL, test ma'lumotlari).

Hammasi birga yuklanadi; ziddiyat bo'lsa aniqroq (loyiha) yo'riqnoma ustun deb hisoblang.

## Muhim: CLAUDE.local.md ni gitignore'ga qo'shing

`CLAUDE.local.md` shaxsiy fayl — u repoga tushmasligi kerak. Loyihaning `.gitignore` fayliga qo'shing:

```
CLAUDE.local.md
```

Agent Hub fayl gitignore'da yo'qligini aniqlasa ogohlantiradi. Parol va tokenlarni hech qaysi CLAUDE faylga yozmang.

## Maslahatlar
- Qisqa va aniq yozing: ro'yxatlar paragraflardan yaxshiroq.
- Boshqa faylni ulash: `@docs/arxitektura.md`.
