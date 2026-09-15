---
id: TASK-10
title: Sessiyalar paneli va yangi sessiya
status: Done
assignee:
  - '@claude'
created_date: '2026-09-15 07:27'
updated_date: '2026-09-15 10:00'
labels:
  - client
  - backend
milestone: m-0
dependencies:
  - TASK-7
  - TASK-8
ordinal: 10000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
O'ng panel: jonli agentlar (blocked tepada va ajratilgan), o'tgan sessiyalar (davom ettirish), Yangi sessiya dialogi, sessiya↔vazifa bog'lanishi.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Jonli agentlar: agent, holat, vaqt, sarlavha; blocked tepada va ajratilgan
- [x] #2 Yangi sessiya dialogi: agent, repo, ixtiyoriy vazifa, prompt; vazifa tanlansa prompt kerakli prefiks bilan boshlanadi
- [x] #3 Bog'lanish ikki tomonda ko'rinadi (kartochkada sessiya, sessiyada vazifa)
- [x] #4 O'tgan sessiya davom ettirish tugmasi asl cwd'da ochadi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Backend: GET /api/sessions/options → {agents: SESSION_AGENTS, prompt_template: SESSION_PROMPT_TEMPLATE} — dialog prefiksni oldindan ko'rsatishi uchun (prompt baribir backend'da build_prompt bilan yig'iladi). pytest.
2. API qatlami: types (SessionOptions, SessionStart, SessionResume), useSessionOptions, usePastSessions(projectId) (?project=), useStartSession/useResumeSession (sessiyalar, loyihalar, doska invalidate).
3. Sof funksiyalar (web/src/sessions/model.ts) + vitest: jonli pane'larni blocked / qolganlarga ajratish, nisbiy vaqt (s/daq/soat/kun), prompt prefiksi (template + task id), agent ro'yxati (health agents ∩ options agents).
4. App: ochiq vazifa holati App'ga ko'tariladi ({projectId, taskId}) — sessiyadagi vazifa bosilsa loyiha tanlanadi va detal ochiladi.
5. O'ng panel: 'Javob kutmoqda' (blocked) alohida bo'lim tepada, keyin 'Jonli agentlar' — agent, holat belgisi (≈ taxminiy), vaqt (oxirgi chiqish/boshlanish), sarlavha, loyiha, vazifa havolasi; 'O'tgan sessiyalar' tanlangan loyiha bo'yicha — sarlavha/recap, agent, vaqt, turns, vazifa, 'Davom ettirish' (faol bo'lsa o'chiq); '+ Sessiya' tugmasi.
6. Yangi sessiya dialogi: agent, repo (loyiha papkalari), ixtiyoriy vazifa (Done bo'lmaganlar), prompt; vazifa tanlansa prefiks read-only ko'rinadi; muvaffaqiyatda yopiladi. Drawer'da 'Sessiya ochish' (vazifa oldindan tanlangan) va bog'langan sessiyalar bo'limi; kartochkada sessiya belgisi (agent + holat).
7. uz lug'ati, uslub.
8. Tekshiruv: make check/build; jonli — izolyatsiyalangan KanBot (vaqtinchalik HOME/KANBOT sozlama, soxta claude/codex skripti PATH'da, SAFE runner) bilan: sessiya ochish (prefiks argv/promptda), bog'lanish kartochka va panelda, blocked tepada, davom ettirish asl cwd'da. Haqiqiy agentlar ishga tushirilmaydi.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Backend: `GET /api/sessions/options` (agentlar + prompt shabloni; KanBot'siz ishlaydi). O'tgan sessiya tirik pane'da ochiq bo'lsa (hook `session_id` yoki argv'dagi `--resume`/`codex resume` ID) `active=true` va resume 409 `session_active` — KanBot faqat 45 s ichida yozilgan faylni active deydi, jim pane'dagi sessiya ikkinchi marta ochilib qolardi (`services/linking.open_session_ids`).
- Frontend: ochiq vazifa va yangi sessiya dialogi holati App'da; SessionsPanel — "Javob kutmoqda" (blocked) alohida qizil bo'lim tepada, keyin jonli agentlar (global), keyin tanlangan loyihaning o'tgan sessiyalari. Vazifa havolasi loyihani tanlab detalni ochadi. Kartochkada agent+holat badge, detalda "Sessiyalar" bo'limi va "+ Sessiya" (vazifa oldindan tanlangan). Dialog prefiksni faqat ko'rsatadi, prompt backend'da yig'iladi. Xatoda (KanBot o'chsa) eski ro'yxat yashiriladi.
- Jonli tekshiruv: izolyatsiyalangan KanBot (KANBOT_HOME/HOME/CLAUDE_CONFIG_DIR scratch'da, port 8797, SAFE runner) + PATH'da soxta `claude`/`codex` skriptlari; haqiqiy agent ishga tushmadi, ~/.kanbot o'zgarmadi.
- Cheklov: soxta agent hook yubormaydi, shuning uchun yangi (resume bo'lmagan) pane sessiyasi o'tganlar ro'yxatida ~45 s dan keyin active=false ko'rindi. Haqiqiy claude hook orqali session_id berishi kutiladi — tekshirilmagan (TASK-12 qo'lda qabulda). Kill va terminal — TASK-11.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Sessiyalar paneli va yangi sessiya dialogi tayyor.

- Jonli agentlar: holat badge (≈ taxminiy), agent, nisbiy vaqt, sarlavha, loyiha va vazifa havolasi; blocked pane'lar tepada alohida qizil "Javob kutmoqda" bo'limida.
- Yangi sessiya dialogi (panel sarlavhasidan yoki vazifa detalidan): agent (oflayn belgisi bilan), repo, ixtiyoriy vazifa, prompt; vazifa tanlansa backend prefiksi oldindan ko'rsatiladi.
- Ikki tomonlama bog'lanish: kartochkada va detalda sessiyalar, sessiyada vazifa havolasi (loyihani tanlab detalni ochadi).
- O'tgan sessiyalar (tanlangan loyiha): "Davom ettirish" asl cwd'da ochadi; tirik pane'da ochiq sessiya uchun tugma o'chiq va backend 409 qaytaradi (yangi `open_session_ids`).
- Backend: `GET /api/sessions/options`.

Tekshiruv: `make check` (ruff, mypy, eslint, tsc, pytest 381, vitest 34) va `make build` o'tdi. Izolyatsiyalangan KanBot + soxta claude/codex bilan brauzerda: vazifali sessiya prompti "Работай только над LEV-001…" bilan boshlandi va kartochka/detal/panelda bog'landi; BLOCK prompti "Javob kutmoqda" bo'limida tepada chiqdi; `demo/sub` dagi eski sessiya resume qilinganda soxta agent `cwd=…/demo/sub` bilan `--resume <id>` oldi; KanBot o'chirilganda panel eski ma'lumotsiz "KanBot ishlamayapti" ko'rsatdi; konsol xatosiz.

Cheklov: hook yubormaydigan agentning yangi sessiyasi o'tganlar ro'yxatida ~45 s dan keyin ochiq deb belgilanmaydi; haqiqiy claude bilan TASK-12 da tekshiriladi.
<!-- SECTION:FINAL_SUMMARY:END -->
