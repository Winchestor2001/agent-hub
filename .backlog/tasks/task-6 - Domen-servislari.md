---
id: TASK-6
title: Domen servislari
status: Done
assignee:
  - '@claude'
created_date: '2026-09-15 07:27'
updated_date: '2026-09-15 08:36'
labels:
  - backend
milestone: m-0
dependencies:
  - TASK-4
  - TASK-5
ordinal: 6000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
linking (task_prefix asosida ID, argv --resume orqali sessiya bog'lash), loyihaga tegishlilik (realpath), summary hisoblagichlari, effective_state (soxta blocked'ni filtrlash), sessiya prompt prefiksi.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Prompt prefiksi talabdagi rus tilidagi matn bilan bayt-bayt mos
- [x] #2 ID bog'lash prefiksga asoslangan: UTF-8 bog'lanmaydi, task-1 == TASK-001
- [x] #3 cwd realpath orqali loyiha papkalariga tegishliligi aniqlanadi; summary hisoblagichlari (status, bug, sessiyalar, blocked) fixture'larga mos
- [x] #4 effective_state: idle notification blocked deb ko'rsatilmaydi; codex holati ≈ belgili
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Tadqiqot (KanBot 0.8.2): claude holati hook'dan (Notification->blocked, Stop->idle); Notification idle kutishda ham keladi -> soxta blocked. Codex holati classify_screen: _BLOCKED regex'da yakka 'permission', 'Would you like to' kabi keng so'zlar bor -> soxta blocked; hook bo'lmasa state_source=screen.
2. services/linking.py (sof funksiyalar): task_id_regex(prefix) — prefiksdan (escape, katta-kichik harf farqsiz, chegaralar bilan), subtask ID'lar (TASK-1.2); canonical_task_id('TASK-001')=='task-1'; find_task_ids(text, prefix); pane_task_id(pane, prefix, session_title) — manbalar tartibi: pane title, argv prompt, resume qilingan sessiya title'i; resume_session_id(argv) — claude '--resume <id>'/'--resume=<id>', codex 'resume [flags] <id>'; project_for_path(cwd, projects) — realpath, eng aniq (eng uzun) papka; is_within(path, dirs).
3. services/state.py: strict tasdiqlash regex'lari (claude: 'Do you want to …', '❯ 1. Yes', "Yes, and don't ask again", 'Do you trust the files'; codex: 'Would you like to run/make/apply', 'Yes, proceed', "don't ask again", 'Allow Codex', '(y/n)'), ekranning oxirgi qatorlarida. EffectiveState(state, approximate, raw_state). StateResolver(read_screen): blocked holatiga o'tishdan oldingi holatni eslab qoladi; blocked + (source=screen yoki oldingi idle/unknown) bo'lsa read_pane(30) bilan tekshiradi, natija last_output_at bo'yicha keshlanadi; so'rov topilmasa idle. Ekranni o'qib bo'lmasa: oldingi idle -> idle, aks holda blocked. approximate = state_source=='screen'. Yo'qolgan pane'lar keshdan tozalanadi.
4. services/sessions.py: SESSION_PROMPT_PREFIX aynan talab matni; build_prompt(task_id, extra); session_title(task_id, title); SessionService(kanbot): start(project, agent, cwd, task_id?, task_title?, extra_prompt) — agent in claude/codex, runner'da capability bor (aks holda agent_unavailable), cwd loyiha papkalari ichida (cwd_outside_project); resume(project, session) — asl cwd (loyiha ichida bo'lishi shart) va runner_id, codex'ga prompt yo'q. Xato: SessionError(code, **params).
5. services/summary.py: ProjectSummary: statuslar config tartibida (+ noma'lum statuslar oxirida), total, bugs (label 'bug' katta-kichik harfsiz yoki type=='bug', har vazifa bir marta; open = oxirgi statusda emas), active_sessions (loyihaga tegishli tirik pane'lar), blocked (effective blocked bor-yo'qligi va soni).
6. Testlar: prompt bayt-bayt (UTF-8 bytes bilan solishtirish), linking parametrlangan (UTF-8, task-1==TASK-001, subtask, boshqa prefiks, so'z ichida emas), realpath (symlink, ../, prefiks-o'xshash papka /a/proj2), state (idle notification, haqiqiy so'rov, codex keng so'z, kesh, o'qish xatosi), sessions (fake kanbot), summary fixture'lar bilan.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Qarorlar:
- Tasdiqlash matnlari Claude Code 2.1.272 va Codex 0.154.0 binar fayllaridagi satrlardan olindi ('Do you want to …?', "Yes, and don't ask again", 'No, and tell Claude/Codex what to do differently', 'Would you like to run the following command?' va boshqalar). Idle belgilari: bo'sh kiritish qatori va '? for shortcuts'. Working belgisi: 'esc to interrupt'.
- classify_screen: tasdiqlash so'rovidan keyin idle qatori bo'lmasa → blocked; working belgisi so'rovdan keyin bo'lsa → working; idle qatori bo'lsa → idle; aniq bo'lmasa None.
- effective_state faqat tirik blocked pane'lar uchun ekranni o'qiydi (read_pane 30, kesh last_output_at bo'yicha, xatolar keshlanmaydi). Ekran aniq bo'lmasa yoki o'qib bo'lmasa: oldingi holat idle bo'lsa idle, aks holda blocked (haqiqiy so'rov yashirilmaydi). Hook 'blocked' ruxsatdan keyin ham qolib ketgan holat ekrandan 'working' deb tuzatiladi. Tuzatilgan va screen-source holatlar approximate=True (≈).
- SessionService runner'ni o'zi tanlaydi: onlayn, agentga ega va auto_approve=false; aks holda agent_unavailable/runner_unsafe. Yangi sessiya cwd'i loyiha papkalaridan biriga (realpath) aynan teng bo'lishi shart. Resume cwd'i esa loyiha ichida bo'lsa yetarli. session_id regex bilan tekshiriladi (argv injection yo'q).
- Prompt testi talab matnining UTF-8 baytlarini foydalanuvchining asl xabaridan olingan hex bilan solishtiradi.
- Bug: label 'bug' (katta-kichik harfsiz) yoki type=bug, har vazifa bir marta; open_bugs — oxirgi statusda bo'lmaganlar.
Tekshiruv: make check yashil (ruff, mypy --strict, eslint, tsc, pytest 345 passed; yangi testlar 90 ta). Haqiqiy Leveling bekloqida summarize natijasi 'backlog task list --json' ga mos keldi (hozir 0 ta vazifa).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
services/ paketi qo'shildi: linking (prefiks asosidagi ID regex, kanonik kalit task-1==TASK-001, resume session_id, realpath bo'yicha loyihaga tegishlilik), state (qat'iy ekran tasnifi va StateResolver: soxta blocked idle yoki working ga tuzatiladi, ≈ belgisi), sessions (talabdagi prompt prefiksi, '<ID> · <sarlavha>' title, faqat claude/codex, xavfsiz runner, loyiha cwd'i, prompt'siz resume), summary (status, bug, faol va blocked sessiyalar). Tekshiruv: test_linking/test_state/test_sessions_service/test_summary (90 test), make check yashil, Leveling'da CLI bilan solishtirildi.
<!-- SECTION:FINAL_SUMMARY:END -->
