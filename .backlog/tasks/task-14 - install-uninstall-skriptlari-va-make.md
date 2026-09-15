---
id: TASK-14
title: install/uninstall skriptlari va make
status: Done
assignee:
  - '@claude'
created_date: '2026-09-15 07:27'
updated_date: '2026-09-15 11:09'
labels:
  - backend
milestone: m-1
dependencies:
  - TASK-13
ordinal: 14000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
scripts/install-services.sh va uninstall-services.sh (idempotent), make install/uninstall/status/logs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 install ikki marta ishga tushirilganda xato bermaydi va o'zgarmagan servisni restart qilmaydi
- [x] #2 Qo'lda ishlayotgan kanbot up (8787), runner yoki tirik pane'lar bo'lsa ogohlantirib to'xtaydi (--force bilan davom)
- [x] #3 make status: 3 job holati, health, aynan 1 runner va auto_approve=false; make logs ishlaydi
- [x] #4 uninstall servislarni to'xtatadi va plist'larni o'chiradi, loglar qoladi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. scripts/services.py (stdlib + render_launchd): install / uninstall / status buyruqlari; launchctl, HTTP va jarayon qidiruvi DI orqali (testlanadi).
2. install: plist'larni render qiladi, ~/Library/LaunchAgents dagisi bilan solishtiradi; o'zgarmagan va yuklangan job'ga tegmaydi, yangi/o'zgarganini bootout -> yozish -> enable -> bootstrap (server, runner, backend tartibida). Log papkasini yaratadi. Oldindan tekshiruv: 8787 (yoki 8700) ni launchd job'i bo'lmagan jarayon egallagan, qo'lda runner ishlayapti yoki tirik pane bor va server/runner qayta ishga tushadi -> ogohlantirib chiqadi, --force bilan davom.
3. uninstall: bootout + plist o'chirish (loglar qoladi), idempotent; tirik pane bo'lsa --force talab qiladi.
4. status: 3 job holati (launchctl print), Agent Hub /api/health, KanBot'da aynan 1 onlayn runner, config va runner'larda auto_approve=false; muammo bo'lsa exit 1.
5. scripts/install-services.sh, uninstall-services.sh (venv python'ga exec); make install (build'dan keyin) / uninstall / status / logs.
6. tests/test_services.py soxta launchctl bilan; qo'lda tekshiruv faqat ruxsat bilan.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Qo'shildi: scripts/services.py (install/uninstall/status, stdlib + render_launchd), scripts/install-services.sh va uninstall-services.sh (.venv python'ga exec), Makefile: install (build'dan keyin), uninstall, status, logs; FORCE=1, LABEL_PREFIX, AGENT_HUB_PORT, KANBOT_PORT, LOG_LINES o'zgaruvchilari.

- install: render natijasi ~/Library/LaunchAgents dagisi bilan solishtiriladi. Bir xil va yuklangan bo'lsa tegilmaydi; bir xil lekin yuklanmagan bo'lsa faqat bootstrap; yangi yoki o'zgargan bo'lsa bootout (to'xtashini kutadi), atomar yozish, enable, bootstrap. Tartib: server, runner, backend. Keyin backend health 30 s kutiladi. Log papkasi yaratiladi.
- Oldindan tekshiruv (--force siz exit 2, hech narsa yozilmaydi): KanBot/Agent Hub portini launchd job'i bo'lmagan PID egallagan (lsof), job'dan boshqa 'kanbot runner|up' jarayoni (pgrep), yoki yuklangan server/runner yangilanadigan holatda tirik pane'lar (KanBot /api/panes).
- uninstall: backend, runner, server tartibida bootout va plist o'chiriladi, loglar qoladi, idempotent; tirik pane'lar bo'lsa --force talab qiladi.
- status: 3 job holati va PID (launchctl print), Agent Hub /api/health va muammolari, KanBot'da aynan 1 onlayn runner, config va runner'larda auto_approve=false; biror narsa noto'g'ri bo'lsa exit 1.

Tekshiruv (foydalanuvchi ruxsati bilan, local.agent-hub-test prefiksi, 8711/8797 portlari, oxirida o'chirildi):
- Qo'lda make dev-kanbot 8797 da ishlayotganda install ogohlantirib exit 2 berdi, plist yozilmadi; --force bilan o'rnatildi, qo'lda server to'xtagach launchd job'i portni oldi.
- make status exit 0: 3 job running, health ok, 1 runner (claude, codex), auto_approve false.
- Ikkinchi make install: 3 ta o'zgarmagan, PID'lar bir xil, launchd jarayonlari begona deb olinmadi.
- O'rnatilgan backend plist o'zgartirilganda faqat backend qayta yuklandi.
- make logs 3 logni ko'rsatdi; begona Origin 403, listener'lar faqat 127.0.0.1.
- make uninstall ikki marta: job'lar va plist'lar yo'q, portlar bo'sh, loglar qoldi.
- tests/test_services.py 16 test; make check yashil (pytest 431, vitest 40).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
launchd servislarini boshqarish qo'shildi: idempotent install (faqat o'zgargan job qayta yuklanadi, qo'lda KanBot/runner yoki tirik pane'lar bo'lsa --force siz to'xtaydi), uninstall (loglar qoladi), status (job'lar, health, aynan 1 runner, auto_approve=false) va make install/uninstall/status/logs. Haqiqiy launchd'da test prefiksi bilan to'liq tsikl tekshirildi va tozalandi; haqiqiy o'rnatish TASK-16 da.
<!-- SECTION:FINAL_SUMMARY:END -->
