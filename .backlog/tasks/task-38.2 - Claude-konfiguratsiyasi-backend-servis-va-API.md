---
id: TASK-38.2
title: 'Claude konfiguratsiyasi: backend servis va API'
status: To Do
assignee: []
created_date: '2026-09-24 16:38'
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
- [ ] #1 Global (settings.claude_home) va loyiha (registrdagi papkalar) qamrovlarida 9 tur uchun ro'yxat, o'qish, yaratish, tahrirlash va o'chirish ishlaydi
- [ ] #2 Fayl yo'li faqat kind katalogi va nom regexidan (harf/raqam/tire, 64 belgigacha) hosil bo'ladi; erkin yo'l, '..' yoki symlink orqali ruxsat etilgan ildizdan tashqariga yozib bo'lmaydi (testlar bor)
- [ ] #3 Yozish atomar; mavjud fayl rejimi saqlanadi (settings.json 0600, hook skriptlari 0755)
- [ ] #4 O'qishda sha256 etag qaytadi; fayl o'zgargan bo'lsa PUT/DELETE 409 qaytaradi; yangi fayl faqat u yo'q bo'lgandagina yaratiladi
- [ ] #5 Yozish va o'chirishdan oldin oldingi nusxa ~/.config/agent-hub/config-backups/ ga saqlanadi
- [ ] #6 settings va .mcp.json JSON sifatida, skills/agents/commands frontmatter sifatida tekshiriladi; xato aniq kod bilan qaytadi
- [ ] #7 Bitta kontentni global va bir nechta loyihaga bir so'rovda yozish (apply) ishlaydi, natija har qamrov uchun alohida qaytadi
- [ ] #8 Global va loyihada bir xil nomli skill/agent bo'lsa, API yopilish (shadowing) belgisini qaytaradi
- [ ] #9 Agent Hub hech narsani commit qilmaydi; yangi xato kodlari uz+ru tarjima qilingan (test_i18n_keys CODE_ARG yangilangan); pytest, ruff, mypy --strict yashil
<!-- AC:END -->
