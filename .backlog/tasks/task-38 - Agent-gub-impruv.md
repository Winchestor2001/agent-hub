---
id: TASK-38
title: Agent gub impruv
status: In Progress
assignee:
  - '@claude'
created_date: '2026-09-24 16:12'
updated_date: '2026-09-24 16:38'
labels: []
dependencies: []
ordinal: 38000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Agent Hub'da Claude Code loyiha tuzilmasini (CLAUDE.md, CLAUDE.local.md, .mcp.json, .claude/settings(.local).json, rules, commands, skills, agents, hooks) UI orqali sozlash, tayyor shablonlar va qo'llanmalar bilan, hamda sessiya ichida modelni UI orqali tanlash. Ish TASK-38.1 dan 38.4 gacha kichik vazifalarga bo'lingan; rejaning umumiy varianti quyidagi Implementation Plan da.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Sessiya ichida model tanlash ishlaydi (TASK-38.1)
- [ ] #2 Konfiguratsiya backend'i xavfsiz yozish bilan ishlaydi (TASK-38.2)
- [ ] #3 Shablonlar va o'zbekcha qo'llanmalar mavjud (TASK-38.3)
- [ ] #4 ConfigView UI global va loyiha qamrovlarida ishlaydi (TASK-38.4)
- [ ] #5 make check yashil
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Ko'lam: Claude Code konfiguratsiyasi (rasmdagi tuzilma): CLAUDE.md, CLAUDE.local.md, .mcp.json, settings(.local).json, rules/, commands/, skills/, agents/, hooks/. Qamrov: global (~/.claude) va loyiha (loyiha papkasi); ikkalasi ixtiyoriy va alohida sozlanadi. Codex keyingi alohida vazifa.

1. Backend servis services/claude_config.py: qamrovlar (global = settings.claude_home yoki ~/.claude; loyiha = registrdagi loyiha papkalari, erkin yo'l qabul qilinmaydi), kind katalogi (nisbiy yo'l, format, nom qoidasi), ro'yxat/o'qish/yozish/o'chirish.
2. Xavfsizlik: nom regex [a-z0-9][a-z0-9-]{0,63}; realpath + is_within, symlink rad; atomar yozish va fayl rejimini saqlash (settings.json 0600, hook skriptlari 0755); sha256 etag bilan optimistik parallellik (409); yozishdan oldin zaxira nusxa (~/.config/agent-hub/config-backups/); JSON va frontmatter tekshiruvi. Agent Hub hech narsani commit qilmaydi.
3. API /api/claude-config: qamrovlar, kind bo'yicha ro'yxat, fayl GET/PUT/DELETE, apply (bitta kontentni bir nechta qamrovga yozish), templates, guides. Yangi xato kodlari uz+ru (test_i18n_keys).
4. Kontent: src/agent_hub/templates/claude/ tayyor shablonlar (skill, command, agent, rule, CLAUDE.md, settings, hook skripti) va qo'llanmalar (uz). Foydalanuvchining o'z .md/.json fayli: yuklash yoki qo'yish.
5. Frontend: TopBar "Konfiguratsiya" tugmasi + loyiha qatorida ⚙ -> butun ekranli ConfigView: qamrov tanlash, kind ro'yxati, element ro'yxati (qidiruv), muharrir, saqlashdan oldin diff, "Shablondan / Fayl yuklash / Qo'llanma", "Qo'llash: Global + bir nechta loyiha", bir xil nom ogohlantirishi (global skill loyiha skilini yopadi), CLAUDE.local.md gitignore ogohlantirishi. Yangi npm bog'liqlik yo'q (qo'llanma uchun kichik ichki markdown render).
6. i18n uz+ru, pytest (xavfsizlik, etag, validatsiya, apply), vitest (model), README bo'limi.
7. make check, brauzerda qo'lda tekshirish, task notes, commit.

Kutilayotgan qarorlar (foydalanuvchi tasdig'i): global MCP (~/.claude.json) fayl orqali emas; settings uchun tuzilmali forma alohida bosqich; vazifani kichik vazifalarga bo'lish.

8. Sessiya ichida model tanlash (foydalanuvchining qo'shimcha talabi): terminal orqali tanlash noqulay va ro'yxatda Opus 4.7/4.8 kabi modellar yo'q.
 8.1 Tekshirilgan faktlar: KanBot 0.8.2 PaneStart faqat agent/prompt/cwd/interactive/resume/title/runner_id qabul qiladi, model maydoni yo'q, shuning uchun sessiya boshlanishida model berib bo'lmaydi; ishlayotgan pane'ga '/model <nom>' + Enter yuborish mumkin (KanBot POST /api/panes/{id}/input). Rasmiy hujjat (code.claude.com model-config, platform.claude.com model-ids-and-versions) bo'yicha ID'lar: claude-fable-5-1, claude-opus-5-5, claude-opus-5, claude-opus-4-8, claude-opus-4-7, claude-opus-4-6, claude-sonnet-5, claude-sonnet-4-6, claude-haiku-4-5-20251001; aliaslar: best, fable, opus, sonnet, haiku, opusplan, [1m] variantlari. Terminal ro'yxatida bo'lmagan model to'liq ID yozilsa ishlaydi. Mahalliy Claude Code 2.1.281.
 8.2 MUHIM yon ta'sir (hujjatdan): '/model <nom>' tanlovni ~/.claude/settings.json dagi 'model' maydoniga yozib, yangi sessiyalar uchun default qiladi. Faqat shu sessiya uchun variant: '/model' pickeri ichida qator ustida 's' bosish.
 8.3 Backend: services/models.py (statik katalog: id, alias, yorliq, oila, current/legacy; foydalanuvchi o'z ID sini kiritishi mumkin), GET /api/models, POST /api/panes/{id}/model {model}: ID regex tekshiruvi; pane tirik, agent=claude va holat idle bo'lishi shart (aks holda 409, matn ruxsat dialogiga tushib ketmasin); kanbot.send_text('/model <id>'). Yangi xato kodlari (model_invalid, pane_not_idle, agent_unsupported) uz+ru.
 8.4 Frontend: TerminalView toolbar'iga ModelPicker (guruhlar: joriy / eski / alias / o'z ID), idle bo'lmaganda o'chirilgan, yuborilgach pane ekranidan tasdiq qatori o'qiladi; vitest + pytest.
 8.5 Hujjatda tasdiqlanmagan: sessiyaning joriy modelini o'qish (transkript formati ichki, tahlil qilish tavsiya etilmaydi) — shuning uchun UI 'joriy model' ni faqat taxminiy (hub yuborgan oxirgi tanlov) ko'rsatadi yoki umuman ko'rsatmaydi.
 8.6 Chegara: Codex '/model' uchun va yangi sessiya dialogida model tanlash (KanBot qo'llamaydi, idle bo'lgach '/model' yuborish kerak, boshlang'ich prompt bilan poyga) — alohida qaror.
Kutilayotgan qarorlar (qo'shimcha): '/model' default'ni o'zgartirishi (A: qabul qilish va UI'da ogohlantirish; B: yuborgach settings.json 'model' ni oldingi qiymatga qaytarish; C: picker'da 's' tugmasini yuborish).
<!-- SECTION:PLAN:END -->
