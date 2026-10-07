---
id: TASK-38.1
title: Sessiya ichida model tanlash (faqat Claude)
status: Done
assignee:
  - '@claude'
created_date: '2026-09-24 16:38'
updated_date: '2026-10-07 11:04'
labels: []
dependencies: []
parent_task_id: TASK-38
ordinal: 39000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Hozir modelni faqat terminaldagi /model pickeri orqali almashtirish mumkin: bu noqulay, ro'yxatda esa Opus 4.7 va 4.8 kabi eski modellar ko'rinmaydi. KanBot 0.8.2 sessiya boshlanishida model qabul qilmaydi (PaneStart da model maydoni yo'q), shuning uchun tanlov ishlab turgan Claude pane'iga '/model <id>' yuborish orqali amalga oshiriladi. Claude Code hujjatiga ko'ra '/model <nom>' tanlovni ~/.claude/settings.json dagi model maydoniga yozadi, ya'ni yangi sessiyalar defaulti ham o'zgaradi; bu foydalanuvchi qarori bilan qabul qilindi (A varianti) va UI'da ogohlantiriladi. Codex va yangi sessiya dialogida model tanlash qamrovdan tashqarida.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Terminal panelida model tanlagich faqat claude agenti uchun ko'rinadi, codex panelida ko'rinmaydi
- [x] #2 Katalogda claude-opus-5-5, claude-opus-5, claude-opus-4-8, claude-opus-4-7, claude-opus-4-6, claude-fable-5-1, claude-sonnet-5, claude-sonnet-4-6, claude-haiku-4-5-20251001 va aliaslar (opus, sonnet, haiku, fable, best, opusplan) bor; foydalanuvchi o'z model ID sini ham kirita oladi
- [x] #3 Tanlash pane'ga '/model <id>' va Enter yuboradi; tirik bo'lmagan, claude bo'lmagan yoki idle holatda bo'lmagan pane uchun backend so'rovni mos xato kodi bilan rad etadi, UI'da tanlagich o'chirilgan
- [x] #4 Noto'g'ri model ID (bo'shliq, boshqaruv belgilari, ruxsat etilmagan belgilar, uzunlik) backendda rad etiladi; ID orqali pane'ga qo'shimcha buyruq yuborib bo'lmaydi
- [x] #5 UI'da '/model yangi sessiyalar uchun ham default bo'ladi' ogohlantirishi uz va ru tilida ko'rinadi
- [x] #6 Yangi xato kodlari uchun uz+ru tarjima bor (test_i18n_keys o'tadi); pytest va vitest testlari yozilgan; make check yashil
- [x] #7 Haqiqiy Claude sessiyasida eski model (masalan claude-opus-4-8) bilan qo'lda tekshirilgan; sinovdan keyin settings.json dagi model qiymati oldingi holatiga qaytarilgan
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Backend services/models.py: statik Claude model katalogi (id, yorliq, guruh: current / legacy / alias) va ID tekshiruvi (bitta token, birinchi belgi harf yoki raqam, faqat harf/raqam/. _ : / - va oxirida ixtiyoriy [1m] kabi qo'shimcha, 200 belgigacha).
2. SessionService.set_model(pane, state, model): tekshiruv tartibi model_invalid (422), model_agent_unsupported, pane_not_alive, pane_not_idle (409), keyin kanbot.send_text('/model <id>', enter=True). Kodlar SessionError orqali, errors.py dagi _SESSION_STATUS ga qo'shiladi.
3. API (api/sessions.py): GET /api/sessions/models -> katalog; POST /api/sessions/{pane_id}/model {model}: pane KanBot'dan olinadi, samarali holat hub.state.resolve orqali (UI ko'rgan idle bilan bir xil), keyin set_model.
4. Frontend: types (SessionModel), queries (useSessionModels, useSetSessionModel), components/ModelPicker.tsx (optgroup: joriy / eski / alias, 'Boshqa ID' maydoni, 'O'zgartirish' tugmasi, default o'zgarishi haqida ogohlantirish), TerminalView toolbar'iga faqat agent=claude uchun; alive va idle bo'lmasa o'chirilgan va sababi ko'rsatiladi. i18n uz+ru (xato kodlari va matnlar).
5. Testlar: pytest (ID tekshiruvi, holatlar, KanBot input yuborilgan matn, xato kodlari, inyeksiya urinishlari), vitest (kerak bo'lsa model yordamchilari), test_i18n_keys.
6. make check; brauzerda qo'lda tekshirish (foydalanuvchi settings.json 'model' ni o'zgartirmaslik uchun joriy defaultga teng model bilan), README qisqa bo'lim, notes, commit.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Backend tayyor: services/models.py (katalog + ID tekshiruvi), SessionService.set_model, GET /api/sessions/models, POST /api/sessions/{id}/model; xato kodlari model_invalid (422), model_agent_unsupported/pane_not_alive/pane_not_idle (409). Frontend: ModelPicker.tsx, TerminalView (faqat claude), i18n uz+ru, README bo'limi. make check yashil: pytest 635, vitest 115, ruff/mypy/eslint/tsc toza.

Tekshiruv (AC #4, #6): tests/test_models.py + tests/api/test_sessions.py (ID inyeksiyasi 'opus\n/exit', bo'shliq, boshqaruv belgilari, uzunlik; working/blocked/done/dead/codex pane rad etiladi). Haqiqiy pane'da (alohida vaqtinchalik backend :8711, yangi test sessiyasi, keyin o'chirildi): working paytida pane_not_idle; idle bo'lgach '/model sonnet' -> 200, pane status qatori 'Sonnet 5'; 'opus\n/exit' -> model_invalid; settings.json dagi model 'sonnet' o'zgarmadi. Katalog AC #2 ro'yxati bilan skript orqali solishtirildi (yetishmaydigan yo'q).

Ochiq: brauzerda UI tekshiruvi bajarilmadi (Chrome kengaytmasi http://127.0.0.1:5173 ni 2 marta 'error page' bilan ochmadi, curl 200 edi). Vaqtinchalik SSR-render skripti (o'chirilgan) uz/ru da guruhlar, 'Opus 4.8 · claude-opus-4-8', 'Boshqa ID…' va working/tugagan pane'da o'chirilgan select + sababni ko'rsatdi, lekin tanlash->yuborish oqimi, default-ogohlantirish (tanlangandan keyin chiqadi) va codex'da ko'rinmasligi haqiqiy DOM'da tekshirilmagan (AC #1, #2-UI, #3-UI, #5). AC #7 (eski model bilan sinov) foydalanuvchi settings.json defaultini vaqtincha o'zgartiradi, shuning uchun ruxsatsiz bajarilmadi.

2026-10-07 brauzer tekshiruvi (Playwright headless Chromium, vaqtinchalik backend :8711, QA papkada yangi claude va codex sessiyalari):
- AC#1: codex terminalida .model-picker 0 ta, claude terminalida 1 ta.
- AC#2: select'da Joriy/Eski/Aliaslar guruhlari, AC ro'yxatidagi 15 ID'ning hammasi bor, 'Boshqa ID…' tanlanganda ID kiritish maydoni chiqadi.
- AC#3/#5: claude-opus-4-8 tanlanganda uz ogohlantirish, til ru'ga almashtirilganda ru ogohlantirish ko'rindi; 'O'zgartirish' -> 'Yuborildi: /model claude-opus-4-8'; yuborilgandan keyin pane working bo'lgani uchun picker o'chdi va 'Model faqat sessiya kutayotganda (idle) o'zgaradi' sababi ko'rindi. Tugagan pane'da select va tugma disabled, sabab 'Sessiya tugagan — model o'zgarmaydi', backend 409 pane_not_alive.
- AC#7: haqiqiy Claude ekranida 'Set model to Opus 4.8 and saved as your default for new sessions', status qatori 'Opus 4.8'. ~/.claude/settings.json oldindan zaxiralangan; farq faqat "model": "claude-opus-4-8" edi, zaxiradan tiklandi (cmp bir xil, model kaliti yo'q - oldingi holat).
- QA pane'lar o'ldirilib KanBot ro'yxatidan olib tashlandi.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Claude sessiyasi ichida model tanlash: TerminalView'da faqat claude uchun ModelPicker (joriy/eski/alias katalogi + ixtiyoriy ID), backend /model <id> ni faqat tirik, idle claude pane'ga yuboradi, noto'g'ri ID va holatlar mos xato kodlari bilan rad etiladi. pytest/vitest va make check yashil; brauzerda (Playwright) codex/claude ko'rinishi, katalog, uz/ru ogohlantirish, yuborish va o'chirilgan holatlar tekshirildi; haqiqiy sessiyada claude-opus-4-8 ga o'tildi va settings.json oldingi holatiga qaytarildi.
<!-- SECTION:FINAL_SUMMARY:END -->
