---
id: TASK-24
title: O'tgan sessiyalarni tanlab o'chirish
status: Done
assignee:
  - '@claude'
created_date: '2026-09-15 16:35'
updated_date: '2026-09-15 18:31'
labels:
  - backend
  - client
dependencies: []
ordinal: 24000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
O'tgan sessiyalar ro'yxati (masalan max-channel-viewer da 12 ta) Claude/Codex transkript fayllaridan keladi va Agent Hub'dan tozalab bo'lmaydi: Claude 30 kundan keyin o'zi o'chiradi, Codex hech qachon. Foydalanuvchi qarori (2026-09-15): yashirish emas, tanlangan sessiyalarning fayllari diskdan butunlay o'chirilsin (tasdiq bilan). KanBot'da o'chirish API'si yo'q; runner har ~6 s da fayllarni qayta skanerlaydi va sessiya yozuvida fayl yo'li (path) bor.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 O'tgan sessiyalar bo'limida sessiyalarni tanlab (bir nechtasini yoki hammasini) o'chirish mumkin; o'chirishdan oldin qaytarib bo'lmasligi haqida tasdiq so'raladi
- [x] #2 O'chirilgan sessiya transkript fayli (Claude: .jsonl va shu ID'li yordamchi papka; Codex: rollout .jsonl) diskdan o'chadi va sessiya ro'yxatdan darhol yo'qoladi
- [x] #3 Ochiq/faol sessiya, boshqa loyihaga tegishli yoki topilmagan sessiya o'chirilmaydi; fayl yo'li Claude/Codex sessiya papkalaridan tashqarida bo'lsa yoki sessiya ID'siga mos kelmasa rad etiladi; xatoda hech narsa o'chirilmaydi
- [x] #4 Backend va frontend testlari; uz/ru matnlar; README yangilangan
- [x] #5 Haqiqiy UI'da tekshirilgan (faqat test uchun yaratilgan sessiya fayllarida)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Topilmalar: KanBot runner discovery (har 6 s) Claude ~/.claude/projects/*/*.jsonl (yoki CLAUDE_CONFIG_DIR) va ~/.codex/sessions/**/rollout-*.jsonl ni o'qiydi, yozuvda path bor; server ro'yxatni runner bo'yicha to'liq almashtiradi. O'chirish API'si yo'q.
1. kanbot_client.AgentSession: path maydoni.
2. services/transcripts.py: agent -> ildiz (claude: CLAUDE_CONFIG_DIR|home/.claude /projects; codex: home/.codex/sessions); session_files: realpath ildiz ichida, .jsonl, fayl nomi sessiya ID'siga mos (claude stem==id, codex ...-id.jsonl), Claude uchun yonidagi <id>/ papka; aks holda session_file_not_found. delete_files.
3. Hub: o'chirilgan (agent, id) to'plami — live() ro'yxatidan chiqaradi, KanBot endi ko'rsatmaganlari to'plamdan tozalanadi (runner qayta skanerlaguncha ro'yxatda qolmasin).
4. API: POST /api/projects/{id}/sessions/delete {sessions:[{agent,session_id}] 1..100}: avval hammasi tekshiriladi (topilmadi 404, boshqa loyiha 404, faol/ochiq 409 session_active, fayl 404 session_file_not_found), keyin o'chiriladi; {deleted}. Xato kodlari uz/ru.
5. Frontend: useDeleteSessions; PastSection: Tanlash rejimi (checkbox, faol sessiya tanlanmaydi, Hammasi), N ta tanlandi · O'chirish -> tasdiq (qaytarib bo'lmaydi) -> o'chirish; sof yordamchilar model.ts da testlari bilan.
6. pytest + vitest, README, make check, build, restart; Chrome'da faqat soxta sessiya fayllarida tekshirish.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Qilindi: settings.transcript_roots (CLAUDE_CONFIG_DIR), AgentSession.path, services/transcripts.py (locate/delete), Hub o'chirilganlarni runner qayta skanerlaguncha yashiradi, POST /api/projects/{id}/sessions/delete, PastSection tanlash rejimi + tasdiq, uz/ru, README. make check: 477 pytest, 67 vitest, lint/tiplar toza. Izolyatsiyalangan instansiya (8711, HOME scratchpad, soxta KanBot 8799) API orqali: ochiq sessiya aralashsa session_active va hech narsa o'chmadi; claude (+ <id>/ papka) va codex o'chdi {deleted:2}, ro'yxatdan darhol yo'qoldi. UI tekshiruvi Chrome ulanmagani uchun kutilmoqda.

UI tekshiruvi (Chrome ulanmagani uchun Playwright headless Chromium, 8711 test instansiya, faqat soxta fayllar): uz — Tanlash rejimi, faol sessiya katakchasi o'chiq, Hammasi 3/0, O'chirish 0 tanlanganda o'chiq, tasdiq matni, Bekor qilish fayllarni saqladi, Butunlay o'chirish claude .jsonl + <id>/ papkani o'chirdi, ro'yxat 4→3 darhol, rejim yopildi; ru — qayta yuklashda 3, codex tanlanib o'chirildi, rollout fayli o'chdi, ro'yxat 2; konsolda xato yo'q. make check: 477 pytest, 67 vitest.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
O'tgan sessiyalarni tanlab diskdan butunlay o'chirish qo'shildi: POST /api/projects/{id}/sessions/delete (1..100 ta; avval hammasi tekshiriladi — boshqa loyiha/topilmadi 404, faol yoki ochiq 409, fayl yo'li Claude/Codex sessiya papkasidan tashqarida yoki ID'ga mos kelmasa session_file_not_found; xatoda hech narsa o'chmaydi), Claude .jsonl + <id>/ papka yoki Codex rollout fayli o'chiriladi, Hub runner qayta skanerlaguncha o'chirilganlarni yashiradi. UI: Tanlash → Hammasi/katakchalar → O'chirish → Butunlay o'chirish tasdig'i. uz/ru, README. Tekshiruv: make check (477 pytest, 67 vitest), izolyatsiyalangan instansiyada API va Playwright UI skripti (uz/ru) faqat soxta fayllarda.
<!-- SECTION:FINAL_SUMMARY:END -->
