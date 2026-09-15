---
id: TASK-11
title: WS proxy va terminal
status: Done
assignee:
  - '@claude'
created_date: '2026-09-15 07:27'
updated_date: '2026-09-15 10:24'
labels:
  - client
  - backend
milestone: m-0
dependencies:
  - TASK-10
ordinal: 11000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Backend WS /ws/panes/{id} → KanBot /ws/web proxy (upstream doim o'qiladi, 2 MB navbat). Frontend TerminalView (xterm.js lokal bundle) markaz o'rnida, tezkor tugmalar bilan.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Terminal markaziy panel o'rnida ochiladi, Doskaga qaytish tugmasi bor; yozish pane'ga yetadi
- [x] #2 Tezkor tugmalar Enter, y, n, Esc, Ctrl-C ishlaydi
- [x] #3 replay terminalni tozalaydi; ikkinchi tab birinchisini buzmaydi
- [x] #4 Test: to'xtab qolgan mijoz upstream'ni bloklamasdan uziladi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Backend: src/agent_hub/api/terminal.py — PaneBridge (transportdan mustaqil): upstream o'quvchi doim ishlaydi, faqat shu pane'ning pane.data/pane.gone xabarlari mijoz navbatiga (2 MB bayt limiti) tushadi; limit oshsa mijoz 'slow_client' (4408) bilan uziladi va upstream yopiladi. Mijoz → upstream: input(data)/keys(validate_keys)/resize, pane_id doim serverda qo'yiladi.
2. WS /ws/panes/{pane_id}?rows=&cols= — KanBot /ws/web ga websockets bilan ulanadi, pane.attach yuboradi; noto'g'ri id 4400, pane yo'q 4404, KanBot o'chiq 4502.
3. Testlar: to'xtab qolgan mijoz upstream'ni bloklamaydi va uziladi; filtr, input tarjimasi, noto'g'ri keys; soxta upstream server bilan WS end-to-end.
4. Frontend: @xterm/xterm + addon-fit (npm, lokal bundle); terminal/protocol.ts (+test); usePaneTerminal; TerminalView markaz o'rnida: sarlavha, Doskaga qaytish, tezkor tugmalar (Enter, y, n, Esc, Ctrl-C), replay'da term.reset(), uzilish holati va qayta ulanish; resize (FitAddon + ResizeObserver). Doska hidden bilan saqlanadi.
5. Ochish nuqtalari: sessiyalar panelidagi jonli pane, vazifa detalidagi sessiya. uz.ts kalitlari.
6. Jonli tekshiruv: izolyatsiyalangan KanBot + soxta agent, ikki tab, tezkor tugmalar; make check/build.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Jonli tekshiruv (izolyatsiyalangan KanBot 8797 + SAFE runner + soxta claude ECHO rejimi, Agent Hub 8711, Chrome):
- Sessiyalar panelidan terminal markazda ochildi, replay ko'rindi; 'salom dunyo'+Enter → pane 'got: [salom\ dunyo]'. '← Doska' doskani qaytardi.
- Tezkor tugmalar: y/n/Enter → got: [y]/[n]/[''], Esc → got: [$'\E'], Ctrl-C → tty ^C echo (0x03 yetdi; fon jarayonda SIGINT ignore bo'lgani uchun trap ishlamadi — bu soxta muhit xususiyati).
- Ikkinchi tab ochilganda KanBot replay yubordi: ikkinchi tab to'liq tarixni ko'rsatdi, birinchi tab reset tufayli matnni takrorlamadi; ikkinchi tabdan yozilgan 'ikkinchi tab' birinchisida ham to'g'ri chiqdi. Konsolda xato yo'q.
- Kuzatuv: KanBot tugagan pane uchun pane.gone yubormaydi (scrollback replay qilinadi, ulanish ochiq qoladi). UI 'tugagan' belgisini jonli ro'yxatdagi alive=false dan oladi; pane.gone faqat noma'lum id'da (4404).
- Tekshiruvlar: make check (ruff, mypy 48 fayl, pytest 405 passed, eslint, tsc, vitest 40 passed), make build OK (faqat chunk >500 kB ogohlantirishi).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Backend WS /ws/panes/{id} → KanBot /ws/web proksi (PaneBridge: upstream doim o'qiladi, mijoz navbati 2 MB, oshsa slow_client 4408; input/keys/resize tarjimasi, pane_id serverda qo'yiladi; 4400/4404/4502 yopilish kodlari) va frontend TerminalView (xterm 6 + addon-fit lokal bundle) markaziy panel o'rnida: Doskaga qaytish, Enter/y/n/Esc/Ctrl-C tugmalari, replay'da reset, qayta ulanish, resize. Ochish: sessiyalar paneli va vazifa detali. Tekshiruv: 24 backend test (shu jumladan to'xtab qolgan mijoz upstream'ni bloklamaydi, soxta KanBot WS bilan e2e), protocol vitest, Chrome'da soxta agent bilan ikki tab jonli sinov; make check va make build o'tdi.
<!-- SECTION:FINAL_SUMMARY:END -->
