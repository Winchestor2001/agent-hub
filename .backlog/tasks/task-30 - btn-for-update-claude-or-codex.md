---
id: TASK-30
title: btn for update claude or codex
status: Done
assignee:
  - '@claude'
created_date: '2026-09-16 05:56'
updated_date: '2026-09-16 06:23'
labels: []
dependencies: []
ordinal: 30000
---

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 btn bosganda codex/claude update qilish ishlasa task done
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Backend servis: src/agent_hub/services/updates.py — brew orqali claude/codex cask'larini boshqarish.
   - AGENT_CASKS: claude -> (claude-code@latest, claude-code), codex -> (codex); o'rnatilgani 'brew list --cask --versions' dan aniqlanadi.
   - status(): 'brew list --cask --versions <tokens>' + 'brew outdated --cask --json=v2 <tokens>' -> installed/latest/outdated; ~60 s kesh, bitta parallel refresh (single-flight), yangilashdan keyin bekor qilinadi.
   - start(agent): fon vazifasi 'brew update --quiet' so'ng 'brew upgrade --cask <token>' (stdin DEVNULL, NO_COLOR/HOMEBREW_NO_ENV_HINTS, timeout 900 s); natija: ok, exit_code, finished_at, chiqishning oxirgi ~20 qatori.
   - Xato kodlari: brew_missing, update_agent_unknown, update_cask_missing, update_running, update_failed. brew yo'li shutil.which + /opt/homebrew/bin, /usr/local/bin fallback.
2. Backend API: src/agent_hub/api/updates.py — GET /api/updates (barcha agentlar holati), POST /api/updates/{agent} (202, fon vazifasini boshlaydi). Hub'ga updates servisi qo'shiladi (deps.py), router app.py ga ulanadi, errors.py ga status xaritasi.
3. launchd: scripts/render_launchd.py PATH_TOOLS ga 'brew' qo'shiladi (backend brew'ni topishi kafolatlansin) + tests/test_launchd.py mos yangilanadi.
4. Frontend: api/types.ts (AgentUpdate, UpdatesResponse), api/queries.ts (useUpdates — yangilash ketayotganda 2 s, aks holda 30 s polling; useStartUpdate).
5. Frontend UI: components/UpdateButtons.tsx — TopBar'da 2 ta tugma: '⬆ claude 2.1.272', yangi versiya bo'lsa nuqta belgisi va tooltipda yangi versiya. Bosilganda tasdiq oynasi (Modal): brew buyrug'i va shu agentning jonli sessiyalari soni haqida ogohlantirish (bloklamaydi). Ishlayotganda spinner + o'chirilgan tugma, tugagach '✓ yangi versiya' yoki xato (ErrorText + brew chiqishi oxiri). TopBar.tsx ga ulanadi; App.tsx tegilmaydi.
6. i18n: uz.ts va ru.ts ga updates.* kalitlari va yangi backend xato kodlari kalitlari; styles.css ga kichik uslublar (tugma, nuqta, spinner).
7. Testlar: tests/test_updates.py (brew chiqishini parslash, cask aniqlash, update_running guard, xato natijasi, API marshrutlari soxta runner bilan), web'da updates model helper testi (vitest), test_i18n_keys avtomatik tekshiradi.
8. README: yangilash tugmalari haqida qisqa bo'lim.
9. Tekshirish: make check (lint + typecheck + pytest + vitest), so'ng make build va haqiqiy tugma bilan claude'ni 2.1.272 -> 2.1.273 ga yangilab ko'rish (AC #1).
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Backend: services/updates.py (brew list/outdated bilan holat, ~60 s kesh, fon vazifasida 'brew update --quiet' + 'brew upgrade --cask'; agent uchun bitta yangilash — update_running), api/updates.py (GET /api/updates, POST /api/updates/{agent} -> 202). errors.py da yangi kodlar: brew_missing 503, update_agent_unknown 404, update_cask_missing 409, update_running 409. launchd PATH'ga brew qo'shildi.

Frontend: updates/model.ts (updateTone/canUpdate/livePaneCount), components/UpdateButtons.tsx — TopBar'da 2 ta tugma (agent + o'rnatilgan versiya, yangi versiya bo'lsa sariq nuqta, ketayotganda '…', tugagach '✓'/'✗'), tasdiqlash oynasida brew buyrug'i, shu agentning jonli sessiyalari soni haqida ogohlantirish (bloklamaydi) va xatoda brew chiqishi. i18n uz/ru + styles.css.

Muhim tuzatish (real muhitda topildi): 'brew outdated' eskirgan paket topsa exit 1 qaytaradi — shuning uchun muvaffaqiyat chiqish kodidan emas, JSON o'qilganidan aniqlanadi (parse_outdated None faqat haqiqiy xatoda). Aks holda latest_version doim null bo'lib qolardi.

Tekshiruv: uv run pytest -q — 553 passed (shundan tests/test_updates.py 21 ta), vitest — 85 passed, ruff + mypy --strict toza (ruff format tests/test_uploads.py da xato beradi — u parallel ishlayotgan TASK-29 fayli, tegilmadi). make build o'tdi.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
TopBar'ga claude va codex uchun brew orqali yangilash tugmalari qo'shildi (backend: /api/updates fon vazifasi bilan, frontend: holat/nuqta/tasdiqlash oynasi, i18n uz+ru, README). AC #1 real tekshirildi: ishlayotgan backend'ga POST /api/updates/claude yuborilib, 'brew upgrade --cask claude-code@latest' bajarildi va claude-code 2.1.272 -> 2.1.273 ga yangilandi (last.ok=true, exit_code=0, keyin installed_version=2.1.273, outdated=false). Avtomatik tekshiruvlar: pytest 553, vitest 85, ruff, mypy --strict.
<!-- SECTION:FINAL_SUMMARY:END -->
