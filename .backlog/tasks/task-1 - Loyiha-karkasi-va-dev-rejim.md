---
id: TASK-1
title: Loyiha karkasi va dev-rejim
status: To Do
assignee: []
created_date: '2026-09-15 07:27'
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
- [ ] #1 pyproject (uv, src/agent_hub), web/ (Vite+React+TS), Makefile yaratilgan
- [ ] #2 make check o'tadi: ruff, mypy --strict, pytest, eslint, tsc --noEmit
- [ ] #3 python -m agent_hub faqat 127.0.0.1:8700 da tinglaydi (port sozlanadi), statikani SPA fallback bilan beradi
- [ ] #4 make dev: KanBot (server + runner --safe) va Agent Hub'ni qo'lda ishga tushirish tartibi hujjatlangan (README 'Dev-rejim' bo'limi qoralamasi)
<!-- AC:END -->
