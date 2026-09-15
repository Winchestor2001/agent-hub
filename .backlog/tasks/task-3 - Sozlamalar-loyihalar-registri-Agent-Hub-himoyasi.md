---
id: TASK-3
title: 'Sozlamalar, loyihalar registri, Agent Hub himoyasi'
status: Done
assignee:
  - '@claude'
created_date: '2026-09-15 07:27'
updated_date: '2026-09-15 07:56'
labels:
  - backend
milestone: m-0
dependencies:
  - TASK-1
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
settings.py (host 127.0.0.1, port, kanbot_url), registry.py (~/.config/agent-hub/projects.yaml, atomar yozish), security.py (Host/Origin middleware HTTP va WS uchun).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 projects.yaml yo'q bo'lsa Leveling (~/my-projects/leveling-backend) bilan yaratiladi; saqlash atomar
- [x] #2 repos bo'sh bo'lsa [backlog_dir]; noto'g'ri yo'l — path_invalid, bekloqsiz papka — backlog_not_found
- [x] #3 Begona Host yoki Origin Agent Hub'da HTTP va WS uchun 403 oladi; testlar bor
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. settings.py: frozen Settings(host=127.0.0.1 doimiy, port, kanbot_url, config_dir, projects_file, kanbot_config, extra_origins). Manba: env (AGENT_HUB_PORT, AGENT_HUB_KANBOT_URL, AGENT_HUB_CONFIG_DIR, AGENT_HUB_EXTRA_ORIGINS, KANBOT_HOME) > ~/.config/agent-hub/config.yaml (ixtiyoriy: port, kanbot_url) > default. kanbot_url faqat http://127.0.0.1|localhost (tashqi so'rov yo'q); noto'g'ri qiymat -> SettingsError.
2. registry.py: Project{id, name, backlog_dir, repos[]} (pydantic), projects.yaml; fayl yo'q bo'lsa Leveling (~/my-projects/leveling-backend) bilan yaratiladi; atomar saqlash (shu papkada temp + fsync + os.replace); threading.Lock; list/get/add/remove. Validatsiya: yo'l mavjud papka emas -> path_invalid; backlog_dir da .backlog/config.yml | backlog/config.yml | backlog.config.yml yo'q -> backlog_not_found; repos bo'sh -> [backlog_dir]; dublikat id -> project_exists; noma'lum -> project_not_found. Xato: RegistryError(code, params).
3. security.py: HostOriginGuard (toza ASGI, HTTP + WS): Host faqat 127.0.0.1|localhost|[::1]:port; Origin bo'lsa o'z origin'lari + extra_origins; rad -> 403 JSON {code: forbidden_host|forbidden_origin, params}, WS accept'dan oldin close 1008 (uvicorn 403).
4. app.py/__main__.py: create_app(settings) guard bilan o'raladi, lifespan'da registry.load() (fayl yaratiladi), app.state.registry; kanbot_url/kanbot_config settings'dan. make dev AGENT_HUB_EXTRA_ORIGINS=http://127.0.0.1:5173 (faqat dev), vite proxy changeOrigin (Host) — Origin qayta yozilmaydi.
5. Testlar: settings (env/yaml/xatolar), registry (default yaratish, atomarlik — xato bo'lsa eski fayl butun, validatsiya kodlari, round-trip), security (HTTP/WS/preflight/Host), app testlari tmp settings bilan (haqiqiy ~/.config ga yozmaydi).
6. make check; jonli: make dev -> ~/.config/agent-hub/projects.yaml yaratiladi, curl evil Origin/Host -> 403, o'z origin -> 200, WS evil -> 403.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Qarorlar: Settings (env > config.yaml > default; host doimiy 127.0.0.1; kanbot_url faqat loopback http). Registry validatsiyasi validate_project() da (API qo'shishda ishlatiladi, TASK-7); fayldan o'qishda yo'llar faqat normallashtiriladi, mavjud bo'lmagan Leveling ham registrda qoladi. Qo'shimcha kodlar: project_id_invalid, project_name_empty, project_exists, project_not_found, registry_invalid. Guard 403 javobi {code: forbidden_host|forbidden_origin, params}. create_app(settings) — test uchun, create_asgi_app(settings) — guard bilan o'ralgan server ilovasi; lifespan'da registry.load(). Dev: make dev AGENT_HUB_EXTRA_ORIGINS=5173, vite proxy changeOrigin (Origin qayta yozilmaydi — 5173 orqali CSRF bypass bo'lmasligi uchun). scripts/kanbot_guarded_server.py dagi guard alohida qoladi (KanBot venv agent_hub'ni import qila olmaydi).

Tekshiruv: make check exit 0 (87 passed). Jonli (make dev): ~/.config/agent-hub/projects.yaml Leveling bilan yaratildi (0600, temp fayl qolmadi); Origin'siz, o'z origin va 5173 -> 200; evil Origin POST -> 403 forbidden_origin; evil Host -> 403 forbidden_host; evil Origin WS /ws/panes/x -> 403 (guard logida); lsof faqat 127.0.0.1:8700. Server to'xtatildi.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
settings.py (env > ~/.config/agent-hub/config.yaml > default, host doim 127.0.0.1, KanBot URL faqat loopback), registry.py (projects.yaml; yo'q bo'lsa Leveling bilan yaratiladi; temp+fsync+os.replace atomar saqlash; path_invalid / backlog_not_found / project_exists va boshqa kodlar; repos bo'sh -> [backlog_dir]) va security.py (HTTP+WS Host/Origin guard, 403 {code, params}) qo'shildi; ilova guard bilan o'raldi, make dev va Vite proxy moslashtirildi, README'ga Sozlamalar bo'limi. Tekshiruv: settings/registry/security testlari (jami 87 passed, atomarlik xato holatida eski fayl butunligi bilan), make check yashil, make dev bilan jonli curl/WS tekshiruvi.
<!-- SECTION:FINAL_SUMMARY:END -->
