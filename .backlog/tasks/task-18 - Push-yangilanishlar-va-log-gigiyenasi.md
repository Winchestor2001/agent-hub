---
id: TASK-18
title: Push yangilanishlar va log gigiyenasi
status: Done
assignee:
  - '@claude'
created_date: '2026-09-15 07:27'
updated_date: '2026-09-15 12:08'
labels:
  - backend
  - client
milestone: m-2
dependencies:
  - TASK-16
ordinal: 18000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
KanBot /ws/web hodisalarini SSE orqali UI'ga uzatish; loglarni tozalash.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Pane holati UI'ga ≤1 s da yetadi; polling zaxira sifatida qoladi
- [x] #2 make logs-truncate mavjud
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Backend api/events.py: EventHub — obunachi bo'lganda KanBot /ws/web ga bitta upstream ulanish (lazy), hodisalarni mavzularga (sessions/health) aylantiradi; har obunachiga birlashtiriladigan (coalescing) to'plam — sekin brauzer KanBot oqimini to'xtatmaydi; uzilsa backoff bilan qayta ulanadi va hamma mavzularni belgilaydi; obunachi qolmasa upstream yopiladi. Hub app.state.events da (deps bilan aylanma import bo'lmasin); upstream ulanish terminal.py open_upstream bilan umumiy.
2. GET /api/events (SSE) — ready, invalidate {topics}, 15 s ping; HostOriginGuard ostida. uvicorn timeout_graceful_shutdown=3, ochiq oqimlar launchd to'xtatishini ushlamasin.
3. Frontend api/events.ts: EventSource + mavzu → queryKey xaritasi; invalidate; qayta ulanganda hammasi yangilanadi; polling o'zgarishsiz zaxira.
4. make logs-truncate: services.py logs-truncate — ~/Library/Logs/agent-hub/*.log joyida 0 ga qisqartiriladi (launchd O_APPEND), hajmlar chiqariladi; README.
5. Testlar: EventHub (soxta upstream), SSE e2e (soxta KanBot WS), vitest xarita, services truncate; make check.
6. Jonli tekshiruv: haqiqiy servislar bilan KanBot hodisalari SSE ga yetishi.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Qilindi: backend /api/events (SSE, EventHub: bitta upstream, obunachi bo'yicha birlashtirish, backoff, xato bir marta loglanadi), frontend useLiveEvents (mavzu → queryKey invalidate, polling o'zgarishsiz zaxira), make logs-truncate (joyida 0 ga, O_APPEND), README. make check: pytest 451, vitest 45. E2E test (haqiqiy uvicorn + soxta KanBot WS): invalidate < 1 s. Backend kickstart qilindi, graceful shutdown tez. Qoldi: haqiqiy servislar bilan jonli kechikish o'lchovi (brauzer kengaytmasi ulanmagan, localhost curl classifier tomonidan bloklangan — foydalanuvchi ishga tushiradi).

Jonli tekshiruv (foydalanuvchi sse_latency.py ni ishga tushirdi, 90 s): haqiqiy KanBot /ws/web → /api/events ishlaydi — ready 0.04 s, keyin har ~7 s invalidate sessions. Sabab (KanBot manbasi): runner _discover_loop har 6 s pane ro'yxatini yuboradi, server set_panes har safar panes.updated broadcast qiladi — o'zgarish bo'lmasa ham; bu polling (2.5 s) dan siyrak, qo'shimcha yuk kichik. Holat o'zgarishida runner _pane_state darhol pane.updated yuboradi, spawn darhol pane ro'yxatini yuboradi — ya'ni yo'l hodisaga asoslangan; Agent Hub qatlami ≤50 ms birlashtirish qo'shadi (e2e testda < 1 s). Sessiya ochib real holat o'zgarishi o'lchanmadi (agent ishga tushirilmadi).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
KanBot /ws/web hodisalari SSE (GET /api/events) orqali UI ga uzatiladi: backend faqat eskirgan mavzuni (sessions/health) yuboradi, frontend useLiveEvents tegishli react-query so'rovlarini invalidate qiladi; polling zaxira sifatida o'zgarishsiz. EventHub bitta lazy upstream, obunachi bo'yicha birlashtirish (sekin brauzer KanBot'ni to'xtatmaydi), backoff bilan qayta ulanish va xatoni bir marta loglash. uvicorn graceful shutdown 3 s. make logs-truncate loglarni joyida 0 ga qisqartiradi (O_APPEND, inode saqlanadi); README yangilandi. Tekshiruv: make check (ruff, mypy, pytest 451, eslint, tsc, vitest 45); e2e test haqiqiy uvicorn + soxta KanBot WS bilan invalidate < 1 s; jonli: haqiqiy KanBot hodisalari /api/events ga yetdi; logs-truncate sinov HOME da ishlatildi.
<!-- SECTION:FINAL_SUMMARY:END -->
