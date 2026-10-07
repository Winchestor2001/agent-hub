---
id: TASK-38.2
title: 'Claude konfiguratsiyasi: backend servis va API'
status: Done
assignee:
  - '@claude'
created_date: '2026-09-24 16:38'
updated_date: '2026-10-07 11:14'
labels: []
dependencies: []
parent_task_id: TASK-38
ordinal: 40000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CLAUDE.md, CLAUDE.local.md, .mcp.json, .claude/settings(.local).json, rules/, commands/, skills/<nom>/SKILL.md, agents/ va hooks/ hozir faqat qo'lda tahrirlanadi. Agent Hub ularni global (~/.claude) va loyiha qamrovlarida xavfsiz ko'rish va yozish uchun backend beradi; ikkala qamrov ixtiyoriy va alohida sozlanadi. Hooks va settings kod ishga tushiradigan konfiguratsiya, shuning uchun yozish qat'iy cheklangan. Global MCP (~/.claude.json) qamrovga kirmaydi: bu Claude'ning jonli holat fayli va uni fayl orqali tahrirlash qarori bilan chiqarib tashlangan. settings uchun tuzilmali forma keyingi alohida bosqich.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Global (settings.claude_home) va loyiha (registrdagi papkalar) qamrovlarida 9 tur uchun ro'yxat, o'qish, yaratish, tahrirlash va o'chirish ishlaydi
- [x] #2 Fayl yo'li faqat kind katalogi va nom regexidan (harf/raqam/tire, 64 belgigacha) hosil bo'ladi; erkin yo'l, '..' yoki symlink orqali ruxsat etilgan ildizdan tashqariga yozib bo'lmaydi (testlar bor)
- [x] #3 Yozish atomar; mavjud fayl rejimi saqlanadi (settings.json 0600, hook skriptlari 0755)
- [x] #4 O'qishda sha256 etag qaytadi; fayl o'zgargan bo'lsa PUT/DELETE 409 qaytaradi; yangi fayl faqat u yo'q bo'lgandagina yaratiladi
- [x] #5 Yozish va o'chirishdan oldin oldingi nusxa ~/.config/agent-hub/config-backups/ ga saqlanadi
- [x] #6 settings va .mcp.json JSON sifatida, skills/agents/commands frontmatter sifatida tekshiriladi; xato aniq kod bilan qaytadi
- [x] #7 Bitta kontentni global va bir nechta loyihaga bir so'rovda yozish (apply) ishlaydi, natija har qamrov uchun alohida qaytadi
- [x] #8 Global va loyihada bir xil nomli skill/agent bo'lsa, API yopilish (shadowing) belgisini qaytaradi
- [x] #9 Agent Hub hech narsani commit qilmaydi; yangi xato kodlari uz+ru tarjima qilingan (test_i18n_keys CODE_ARG yangilangan); pytest, ruff, mypy --strict yashil
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. services/claude_config.py: Kind katalogi (claude_md, claude_local_md, mcp, settings[settings|settings-local], rules, commands, skills, agents, hooks), Scope (global = claude_home; project:<id>[:n] = registrdagi papkalar), nom regex [a-z0-9][a-z0-9-]{0,63} (hook: + .sh/.js/.mjs/.cjs/.py).
2. Xavfsizlik: ildiz realpath, ildiz ostidagi har bo'g'in symlink bo'lsa rad; atomar yozish (mkstemp + fsync + replace, yaratishda os.link bilan create-if-absent); mavjud rejim saqlanadi, yangi: settings 0600, hook 0755, qolgan 0644; sha256 etag + lock bilan CAS (409 config_conflict / config_exists); config_dir/config-backups ga zaxira (0600).
3. Validatsiya: JSON obyekt (settings, .mcp.json: mcpServers obyekt), frontmatter (skills: description; agents: name+description; commands/rules: ixtiyoriy, lekin YAML mapping), 512 KB, UTF-8.
4. Shadowing: skill — global ustun, agent — loyiha ustun; ro'yxatda har element uchun shadow [{scope, winner}].
5. CLAUDE.local.md: git check-ignore orqali gitignore ogohlantirishi (faqat o'qish).
6. API /api/claude-config: scopes, items, file GET/PUT/DELETE, apply (har qamrov natijasi alohida). Xato kodlari uz+ru, CODE_ARG ga ConfigError.
7. pytest: path traversal, symlink, rejim, etag, zaxira, validatsiya, apply, shadow; ruff, mypy.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Qarorlar: settings turi ikki qat'iy nomli (settings, settings-local) — 9 tur saqlandi. Hook nomi = stem regex + .sh/.js/.mjs/.cjs/.py (~/.claude/hooks da .js hooklar bor). Ko'p papkali loyiha uchun har papka alohida qamrov: project:<id> (asosiy), project:<id>:<n>. Global ~/.claude yo'q bo'lsa o'qish 'yo'q' qaytaradi, birinchi yozishda yaratiladi. Regexga mos kelmagan nomlar ro'yxatda 'skipped' sifatida qaytadi (haqiqiy ~/.claude: gsd-extract_learnings). Symlink element ro'yxatda symlink=true, o'qish/yozish rad. CLAUDE.local.md o'qilganda git check-ignore bilan 'local_not_ignored' ogohlantirishi (faqat o'qish, git'ga yozilmaydi).
Tekshiruv: tests/test_claude_config.py (60) + tests/api/test_claude_config.py (6) — traversal/regex, symlink papka va fayl, 0600/0755/0644 va mavjud rejim, os.replace xatosida eski fayl va temp qolmasligi, etag 409 (PUT/DELETE), config_exists, zaxira 0600, JSON/frontmatter kodlari, shadowing (skill global ustun, agent loyiha ustun), apply har qamrov natijasi. To'liq pytest 712 passed, ruff check/format, mypy --strict toza; test_i18n_keys (CODE_ARG ga ConfigError) yashil. Haqiqiy ~/.claude ustida faqat o'qish: 90 skill, 33 agent, 12 hook, settings 0600 to'g'ri ro'yxatlandi.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
services/claude_config.py (tur katalogi, qamrovlar, xavfsiz atomar yozish, etag CAS, zaxira, validatsiya, shadowing, apply) va /api/claude-config (scopes, items, file GET/PUT/DELETE, apply) qo'shildi; 20 ta yangi xato kodi uz+ru. pytest (66 yangi test, jami 712), ruff, mypy --strict yashil; haqiqiy ~/.claude ustida faqat o'qib tekshirildi.
<!-- SECTION:FINAL_SUMMARY:END -->
