---
id: TASK-1
title: Loyiha karkasi va dev-rejim
status: Done
assignee:
  - '@claude'
created_date: '2026-09-15 07:27'
updated_date: '2026-09-15 07:37'
labels:
  - backend
  - client
milestone: m-0
dependencies: []
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
uv + FastAPI (Python 3.12) backend va Vite + React + TS frontend skeleti. Bitta jarayon: FastAPI build qilingan statikani beradi. Makefile va sifat vositalari. launchd'siz ishga tushirish uchun dev-rejim.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 pyproject (uv, src/agent_hub), web/ (Vite+React+TS), Makefile yaratilgan
- [x] #2 make check o'tadi: ruff, mypy --strict, pytest, eslint, tsc --noEmit
- [x] #3 python -m agent_hub faqat 127.0.0.1:8700 da tinglaydi (port sozlanadi), statikani SPA fallback bilan beradi
- [x] #4 make dev: KanBot (server + runner --safe) va Agent Hub'ni qo'lda ishga tushirish tartibi hujjatlangan (README 'Dev-rejim' bo'limi qoralamasi)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. pyproject.toml (uv, Python 3.12, src/agent_hub): fastapi, uvicorn, httpx, websockets, pydantic, pyyaml; dev: ruff, mypy, pytest, pytest-asyncio, respx
2. src/agent_hub: __main__.py (uvicorn, host qat'iy 127.0.0.1, AGENT_HUB_PORT, access log o'chiq), app.py (create_app, /api/health stub, statik + SPA fallback; /api va /ws yo'llari fallback'ga tushmaydi)
3. web/: Vite + React + TS, ESLint flat config, build natijasi src/agent_hub/static ga
4. tests: host bog'lanishi, SPA fallback, /api 404 JSON
5. Makefile: sync, build, lint, typecheck, test, check, dev, dev-web, dev-kanbot, dev-runner
6. README qoralamasi: Dev-rejim bo'limi (KanBot server + runner --safe + Agent Hub qo'lda)
7. make check ni ishga tushirib tekshirish, commit
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Qarorlar: TypeScript 6.0.3 (typescript-eslint 8.70 TS 7 ni qo'llamaydi). static/ build natijasi gitignore'da. SPA handler sync (ASYNC240). Dev-rejimda KanBot hozircha oddiy 'kanbot server' bilan — TASK-2 da himoya launcher'iga almashtiriladi.
Tekshiruv: make check exit 0 (ruff, format, mypy strict, 8 pytest, eslint, tsc); python -m agent_hub lsof bo'yicha 127.0.0.1:8700 LISTEN, LAN IP orqali ulanmaydi; AGENT_HUB_PORT=8711 ishlaydi; SPA fallback va /api 404 JSON curl bilan tekshirildi; make -n dev-kanbot/dev-runner buyruqlarni ko'rsatadi.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
uv+FastAPI backend (python -m agent_hub, faqat 127.0.0.1, port AGENT_HUB_PORT orqali, statik+SPA fallback), Vite+React+TS frontend (build -> src/agent_hub/static), Makefile (sync/build/lint/typecheck/test/check/dev/dev-web/dev-kanbot/dev-runner) va README'da Dev-rejim bo'limi. Tekshiruv: make check yashil, curl+lsof bilan loopback bog'lanish va SPA tasdiqlandi.
<!-- SECTION:FINAL_SUMMARY:END -->
