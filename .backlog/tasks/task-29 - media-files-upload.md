---
id: TASK-29
title: media files upload
status: Done
assignee:
  - '@claude'
created_date: '2026-09-16 05:53'
updated_date: '2026-09-16 06:42'
labels: []
dependencies: []
ordinal: 29000
---

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 file/rasim yuklasa bo`lsa task done
- [x] #2 Vazifa In Progress ga o'tganda sessiya dialogi oldindan to'ldirilgan holda avtomatik ochiladi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Maqsad: Agent Hub orqali rasm/fayl yuklab, uni claude/codex ga uzatish; vazifa In Progress ga
o'tganda sessiya dialogini oldindan to'ldirilgan holda ochish.

Saqlash joyi: <loyiha papkasi>/.agent-hub/uploads/<task-29|inbox>/<YYYYMMDD-HHMMSS>-<nom>.
Papkada o'zini-o'zi e'tiborsiz qoldiruvchi .gitignore (`*`) yaratiladi — repo .gitignore tegilmaydi.
Prompt/tavsifga NISBIY yo'l yoziladi (cwd = loyiha papkasi), shuning uchun agent ruxsatsiz o'qiydi.

1. Bog'liqlik: pyproject.toml ga `python-multipart` (FastAPI UploadFile talab qiladi), `make sync`.

2. src/agent_hub/services/uploads.py (yangi):
   - ALLOWED_EXTENSIONS: png jpg jpeg gif webp heic pdf txt md csv json log yaml yml
   - MAX_FILE_BYTES = 10 MiB, MAX_FILES = 10
   - safe_name(): faqat basename, [A-Za-z0-9._-] ga slug, uzunlik 80, kengaytma allowlist'da
   - upload_dir(project, cwd, task_id): cwd project.dirs ichida bo'lishi shart (services/sessions.py
     _project_dir bilan bir xil tekshiruv), natija real_path + is_within bilan qayta tasdiqlanadi
   - save(): chunk-chunk yoziladi, limitdan oshsa yarim fayl o'chiriladi; nom to'qnashsa -1, -2
   - resolve_uploads(paths): mijoz qaytargan nisbiy yo'llar aynan uploads papkasi ichida va mavjud
   - UploadError kodlari: upload_too_large, upload_type_invalid, upload_name_invalid,
     upload_too_many, upload_empty, cwd_outside_project

3. src/agent_hub/api/uploads.py (yangi router, app.py ga ulanadi):
   POST /api/projects/{project_id}/uploads  (multipart: files[], cwd?, task_id?)
   -> {\"files\": [{\"name\", \"path\" (nisbiy), \"size\", \"kind\": image|file}]}
   Xatolar api/errors.py xarita orqali (413/415/422).

4. Prompt/tavsifga fayllarni qo'shish (server tomonda, yagona nuqta):
   - services/sessions.py: build_prompt(task, extra, files) — oxiriga
     \"Прикреплённые файлы:\" + nisbiy yo'llar ro'yxati; SessionStart.files qo'shiladi
   - api/tasks.py: TaskCreate.files qo'shiladi; tavsif oxiriga shu ro'yxat biriktiriladi
   Ikkala joyda ham yo'llar resolve_uploads() bilan tekshiriladi.

5. Frontend:
   - api/client.ts: postForm() (FormData, JSON emas) + queries.ts: useUploadFiles(projectId)
   - components/FileAttach.tsx (yangi): fayl tanlash tugmasi, drag&drop zonasi, Ctrl+V bilan
     skrinshot qo'yish, rasm eskizi, ro'yxatdan olib tashlash; ota komponentga path[] qaytaradi
   - CreateTaskDialog.tsx va NewSessionDialog.tsx ga \"Fayllar\" maydoni; body.files yuboriladi
   - api/types.ts: TaskCreate.files, SessionStart.files, UploadResult

6. In Progress -> sessiya dialogi:
   - board/model.ts: isInProgressStatus(status) — nom bo'yicha (in progress / doing / в работе /
     jarayon), regex, katta-kichik harf farqsiz; mos kelmasa hech narsa ochilmaydi
   - useSetStatus onSuccess -> App.tsx da onStartSession(taskId) chaqiriladi (BoardPanel drag va
     TaskDetailDrawer select — ikkalasi ham), agar vazifada tirik sessiya bo'lmasa
   - Dialog oldindan to'ldiriladi: vazifa tanlangan, cwd = loyiha papkasi; agent/cwd tasdiqlanadi

7. i18n: uz.ts + ru.ts + messages.ts ga barcha yangi error.* va UI kalitlari
   (tests/test_i18n_keys.py shuni talab qiladi).

8. Testlar:
   - tests/test_uploads.py: safe_name (traversal, boshqaruv belgilari, kengaytma), hajm limiti,
     nom to'qnashuvi, cwd loyihadan tashqarida, resolve_uploads escape
   - tests/test_api_uploads.py: TestClient multipart, 201 + xato kodlari
   - tests/test_sessions_service.py: build_prompt fayllar bilan
   - web: FileAttach va isInProgressStatus uchun vitest testlari

9. README: \"Media fayllar\" bo'limi; make check (ruff+mypy+pytest+eslint+vitest+tsc) yashil.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Tekshiruv (jonli server, izolyatsiya qilingan nusxa: AGENT_HUB_CONFIG_DIR=<tmp>, port 8799, vaqtinchalik backlog loyihasi):
- POST /api/projects/demo/uploads (multipart, task_id=TASK-1) -> 201, {path: .agent-hub/uploads/task-1/20260916-112024-sinov-rasm.png, size: 70, kind: image}; diskdagi fayl baytma-bayt manba bilan bir xil (cmp).
- .agent-hub/uploads/.gitignore = '*' o'zi yaratildi; git status yuklangan faylni ko'rsatmaydi (loyiha .gitignore'iga tegilmadi).
- POST /tasks {files: [...]} -> TASK-2; backlog CLI yozgan markdown tavsifida 'Прикреплённые файлы' ro'yxati bor.
- Xato yo'llari jonli tekshirildi: .exe -> 415 upload_type_invalid, 11 MB -> 413 upload_too_large, uploads'dan tashqaridagi 'maxfiy.txt' -> 404 upload_not_found, '../../../../etc/passwd' -> 404 upload_not_found. Rad etilgan fayllardan diskda hech nima qolmadi (find: faqat .gitignore + bitta haqiqiy rasm).

Avtomatik tekshiruvlar (`make check`, ishchi papkada — TASK-30 va TASK-31 bilan birga): ruff, ruff format, mypy --strict, pytest 554 passed, eslint --max-warnings 0, tsc -b --noEmit, vitest 89 passed (12 fayl).

Commit ajratilishi: TASK-30/TASK-31 parallel ishlagani uchun umumiy fayllarda (README.md, api/errors.py, app.py, tests/test_i18n_keys.py, web api/i18n/styles) faqat TASK-29 hunklari commit qilindi; boshqa vazifalarning hunklari ishchi papkada qoldi va o'z commitlarini kutadi. Shu sababli faqat shu commitning daraxtida mypy `api/updates.py` uchun xato beradi (TASK-30 ning app.py ulanishi hali commit qilinmagan) — ishchi papkada esa hammasi yashil.

AC #2 hali belgilanmagan: brauzer kengaytmasi ulanmagani uchun UI orqali bosib tekshirilmadi. Model darajasida isInProgressStatus/shouldOpenSession vitest bilan qoplangan, wiring tsc bilan tekshirilgan — lekin bu AC uchun yetarli dalil emas.

AC #2 UI da tekshirildi: build qilingan frontend bilan backend qayta ishga tushirildi (launchctl kickstart, health ok, runner 1 onlayn), foydalanuvchi doskada vazifani In Progress ga ko'chirib dialog oldindan to'ldirilgan holda ochilishini tasdiqladi.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Agent Hub orqali media fayl biriktirish va vazifa jarayonga o'tganda sessiya dialogini ochish qo'shildi.

Fayllar loyiha papkasidagi `.agent-hub/uploads/<vazifa-id>|inbox/` ga saqlanadi (o'zini e'tiborsiz qoldiruvchi .gitignore bilan), nisbiy yo'l vazifa tavsifiga yoki sessiya promptiga qo'shiladi — shuning uchun claude/codex faylni qo'shimcha ruxsatsiz o'qiydi. Kengaytma allowlist'i (.svg yo'q), 10 MB / 10 fayl chegarasi, nom slug + vaqt belgisi, mijoz yo'llari server tomonda qayta tekshiriladi.

Vazifa In Progress ga o'tganda (sudrab yoki detaldagi statusdan) va tirik sessiyasi bo'lmasa, yangi sessiya dialogi oldindan to'ldirilgan holda ochiladi; o'zi ishga tushirmaydi.

Tekshiruv: AC #1 — jonli izolyatsiya qilingan server (port 8799) ustida HTTP orqali (201 + baytma-bayt cmp, .gitignore avtomatik, tavsifga yo'l yozilishi, 415/413/404 xato yo'llari, rad etilganidan diskda iz qolmasligi). AC #2 — foydalanuvchi UI da tasdiqladi. Avtomatik: make check yashil (pytest 554, vitest 89, ruff, mypy --strict, eslint, tsc). Commit: 49d7951 (faqat TASK-29 hunklari).
<!-- SECTION:FINAL_SUMMARY:END -->
