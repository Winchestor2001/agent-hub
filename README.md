# Agent Hub

Claude Code va Codex sessiyalari (KanBot orqali) hamda Backlog.md vazifalari uchun lokal veb UI.
Bitta brauzer oynasida loyihalar, vazifalar doskasi, agent sessiyalari va ularning jonli terminali.
Manzil: `http://127.0.0.1:8700`. Hammasi faqat `127.0.0.1` da tinglaydi.
Ilova telemetriya yubormaydi va tashqi so'rov qilmaydi.

```
brauzer ──► Agent Hub (127.0.0.1:8700) ──► KanBot server (127.0.0.1:8787) ◄── KanBot runner (--safe)
                 │                                                               │
                 └──► backlog CLI (loyiha papkalarida)                  claude / codex pane'lari
```

- **Agent Hub** (`python -m agent_hub`): FastAPI backend va build qilingan React UI, bitta jarayon.
  Vazifalarni `backlog` CLI orqali o'qiydi va o'zgartiradi, sessiyalarni KanBot REST/WebSocket orqali boshqaradi.
- **KanBot server**: `scripts/kanbot_guarded_server.py` orqali, begona `Host`/`Origin` ni rad etadigan himoya bilan.
- **KanBot runner**: agent CLI'larni pane'larda ishga tushiradi, faqat SAFE rejimda (auto-approve yo'q).

Uchala jarayon launchd servisi sifatida login paytida o'zi ishga tushadi (quyida), yoki dev-rejimda qo'lda.

## Talablar

- macOS, Python 3.12, [uv](https://docs.astral.sh/uv/), Node.js 24 + npm
- [KanBot](https://pypi.org/project/kanbot/) 0.8.x (`uv tool install kanbot`)
- [Backlog.md](https://github.com/MrLesk/Backlog.md) CLI (`backlog`)
- `claude` va/yoki `codex` CLI (obuna orqali avtorizatsiya qilingan; API kalitlari kerak emas)

## O'rnatish (launchd servislari)

1. Bog'liqliklar:

   ```sh
   make sync
   ```

2. KanBot'ni xavfsiz sozlash (bir marta). Xavfli agentlar o'chiriladi:

   ```sh
   kanbot config --disable shell glm kimi
   ```

   `~/.kanbot/config.json` da `auto_approve` `false` bo'lishi kerak. `--safe` bilan ishlagan runner uni o'zi
   `false` qilib yozadi.

3. Qo'lda ishga tushirilgan KanBot (`kanbot up`, `make dev-kanbot`, `make dev-runner`) va `make dev` ni to'xtating.
   Keyin:

   ```sh
   make install
   ```

   Frontend build qilinadi, plist'lar `launchd/*.plist.in` shablonlaridan joriy mashina yo'llari bilan render
   qilinib `~/Library/LaunchAgents` ga yoziladi va yuklanadi. Qayta ishga tushirish xavfsiz: o'zgarmagan
   servislarga tegilmaydi, faqat yangi yoki o'zgargan plist qayta yuklanadi.

   `make install` quyidagi holatlarda ogohlantirib to'xtaydi va hech narsa yozmaydi:
   - 8787 yoki 8700 portini launchd'dan tashqari jarayon egallagan;
   - qo'lda ishga tushirilgan `kanbot runner` / `kanbot up` bor;
   - tirik agent pane'lari bor va KanBot server yoki runner qayta ishga tushishi kerak (pane'lar to'xtaydi).

   Baribir davom etish: `make install FORCE=1`.

4. Tekshirish:

   ```sh
   make status
   ```

   Hammasi joyida bo'lsa exit 0: uchala servis `running`, Agent Hub health `ok`, KanBot'da aynan 1 ta onlayn
   runner, config va runner'da `auto_approve=false`. So'ng `http://127.0.0.1:8700` ni oching.

| Servis (label) | Buyruq | Port | Log |
|---|---|---|---|
| `local.agent-hub.kanbot-server` | KanBot venv python'i + `scripts/kanbot_guarded_server.py` | 8787 | `kanbot-server.log` |
| `local.agent-hub.kanbot-runner` | `kanbot runner --safe --server http://127.0.0.1:8787` | — | `kanbot-runner.log` |
| `local.agent-hub.backend` | `.venv/bin/python -m agent_hub` | 8700 | `backend.log` |

Servislarda `RunAtLoad` va `KeepAlive` yoqilgan: login paytida ishga tushadi, yiqilsa 10 s dan keyin qayta
ko'tariladi. PATH plist'ga render paytida yoziladi (`kanbot`, `claude`, `codex`, `backlog`, `node` papkalari).
CLI'lardan biri boshqa joyga ko'chsa, `make install` ni qayta ishga tushiring.

Boshqa portlar: `make install AGENT_HUB_PORT=8711 KANBOT_PORT=8797` (`make status` va `make uninstall` ga ham
xuddi shu qiymatlarni bering).

## Loyiha qo'shish

UI'da chap paneldagi **+ Loyiha** tugmasi. Yo'llarni yodda tutish shart emas:

- Oynaning tepasida `~/my-projects` dagi hali qo'shilmagan papkalar chiqadi (bekloqlilari birinchi,
  «bekloq bor/yo'q» belgisi bilan). Birini bosish bekloq papkasini, nomni va ID'ni to'ldiradi.
- **Tanlash…** va **+ Papka qo'shish** uy papkasi ichidagi papka brauzerini ochadi (faqat papkalar;
  uydan tashqariga chiqib bo'lmaydi).

Maydonlar nima uchun kerak:

- **Bekloq papkasi** — vazifalar shu papkadagi `.backlog/` yoki `backlog/` dan o'qiladi, `backlog`
  buyruqlari ham shu yerda bajariladi. Odatda asosiy repo.
- **Qo'shimcha repo papkalari** — agent sessiyalari ish papkasi (cwd) bo'yicha loyihaga bog'lanadi.
  Bekloq papkasi har doim loyihaga kiradi va yangi sessiya oynasida birinchi (standart) turadi; loyiha
  boshqa repolardan ham iborat bo'lsa (masalan admin va web), ularni shu yerga qo'shing. Shu papkalar
  ichida ochilgan sessiyalar loyihada ko'rinadi, yangi sessiya ham ulardan birida boshlanadi.

Tanlangan papkada bekloq bo'lmasa, oyna **Bekloq yaratish** tugmasini taklif qiladi. Tasdiqlagandan keyin
`backlog init <nom> --defaults --backlog-dir .backlog --integration-mode none` bajariladi (git bo'lmagan
papkada `--no-git` bilan): faqat `.backlog/` yaratiladi, `CLAUDE.md`/`AGENTS.md` qo'shilmaydi va commit
qilinmaydi. Bekloq allaqachon bor papkada yaratish rad etiladi. Agent Hub hech qachon bekloqni o'zi
avtomatik yaratmaydi.

**Tahrirlash (✎).** Loyiha qatori ustiga kelganda × ostida chiqadi: nom, bekloq papkasi va repo papkalarini
o'zgartirish mumkin (ID o'zgarmaydi). Tekshiruvlar qo'shishdagi bilan bir xil. Saqlangach doska yangi bekloq
papkasidan o'qiladi, sessiyalar esa yangi loyiha papkalari bo'yicha qayta bog'lanadi.

**Ro'yxatdan olib tashlash** faqat Agent Hub ro'yxatini o'zgartiradi, bekloq va fayllarga tegmaydi.

Loyihalarni `~/.config/agent-hub/projects.yaml` da qo'lda ham tahrirlash mumkin (format "Sozlamalar"
bo'limida). Backend fayl o'zgarishini keyingi so'rovda o'qiydi.

## Foydalanish

**Til.** Yuqori paneldagi tanlovda O'zbekcha yoki Русский. Tanlov shu brauzerda saqlanadi (`localStorage`,
`agent-hub.locale` kaliti) va sahifa qayta yuklanganda qoladi; saqlab bo'lmasa (masalan, sayt ma'lumotlari
bloklangan) o'zbekcha ochiladi. Backend xatolari ham tanlangan tilda ko'rsatiladi.

**Yangilanishlar.** Sessiya holati va health o'zgarishi backend'dan push (`/api/events`, SSE) orqali darhol
keladi. Oqim uzilsa ham UI har 2,5 s da (o'tgan sessiyalar — 6 s da) so'rab turadi; jonli sessiyalar
ro'yxati tab fonda bo'lganda ham yangilanadi.

**Sessiyalar paneli.** Jonli, javob kutayotgan va tugagan sessiyalar tanlangan loyiha bo'yicha ko'rsatiladi
(sessiya loyihaga ishchi papkasi — cwd — orqali bog'lanadi). Boshqa loyihalarda yoki loyihadan tashqarida
ochiq sessiyalar bo'lsa, «Jonli agentlar» ostida ularning soni (javob kutayotganlari qizil) yoziladi;
**Hammasini ko'rsatish** barcha loyihalar sessiyalarini ochadi, **Faqat <loyiha>** qaytaradi.

**Javob kutayotgan sessiyalar.** Ruxsat yoki javob kutayotgan agentlar Sessiyalar panelida «Javob kutmoqda»
bo'limida birinchi turadi, soni (barcha loyihalar bo'yicha) tab sarlavhasida ko'rinadi: `(2) Agent Hub`.

- Brauzer bildirishnomasi: yuqori paneldagi **Bildirishnomalar** tugmasini bosib ruxsat bering. Sessiya
  javob kuta boshlaganda, Agent Hub tabi fokusda bo'lmasa bildirishnoma chiqadi; bosilsa shu sessiya
  terminali ochiladi (boshqa loyihada bo'lsa, o'sha loyiha tanlanadi). Ruxsat rad etilgan bo'lsa yuqori panelda «Bildirishnomalar bloklangan» yoziladi — brauzerning
  sayt sozlamalarida `http://127.0.0.1:8700` uchun ruxsat bering.
- Holat hook'lardan olinadi. Hook bo'lmasa (masalan, Codex) holat ekrandan taxminiy aniqlanadi va «≈» bilan
  belgilanadi; bunday sessiyada javob kutish har doim ham aniqlanmaydi.

**Media fayllar.** Vazifa yaratish va yangi sessiya dialoglarida fayl biriktirsa bo'ladi: **Fayl tanlash**,
maydonga sudrab tashlash yoki skrinshotni `Ctrl+V` (macOS: `⌘V`) bilan qo'yish. Fayl darhol loyiha papkasi
ichiga — `.agent-hub/uploads/<vazifa-id>/` yoki vazifa hali yo'q bo'lsa `.agent-hub/uploads/inbox/` ga —
saqlanadi, nomiga vaqt belgisi qo'shiladi (mavjud fayl hech qachon ustiga yozilmaydi). Yo'llar vazifa
tavsifiga yoki sessiya promptiga nisbiy ko'rinishda qo'shiladi, shuning uchun claude/codex ularni o'z ishchi
papkasidan qo'shimcha ruxsatsiz o'qiydi.

- Ruxsat etilgan turlar: `.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`, `.heic`, `.pdf`, `.txt`, `.md`, `.csv`,
  `.json`, `.log`, `.yaml`, `.yml`. `.svg` ataylab qabul qilinmaydi (ichida skript bo'lishi mumkin).
- Chegaralar: bitta fayl 10 MB gacha, bir martada 10 tagacha.
- `.agent-hub/uploads/.gitignore` o'zi yaratiladi (`*`), shuning uchun yuklangan fayllar repoga tushmaydi;
  loyihaning o'z `.gitignore` fayliga tegilmaydi. Keraksiz bo'lsa papkani qo'lda o'chirsa bo'ladi.

**Jarayonga o'tganda sessiya.** Vazifa **In Progress** ustuniga ko'chirilganda (sudrab yoki detaldagi status
tanlovidan) va unda tirik sessiya bo'lmasa, yangi sessiya dialogi shu vazifa oldindan tanlangan holda
ochiladi — agent va papkani tasdiqlab **Boshlash** bosiladi. Dialog o'zi ishga tushirmaydi.

**Terminal va klaviatura.**

| Tugma | Amal |
|---|---|
| Alt+Shift+↓ / ↑ (macOS: ⌥⇧↓ / ↑) | Panelda ko'rinayotgan keyingi / oldingi jonli sessiya terminali (aylanma; avval javob kutayotganlar, keyin boshlanish tartibida). Terminal fokusda bo'lsa ham ishlaydi, matn maydonlarida va dialog ochiqligida ishlamaydi |
| ↑ / ↓ / Home / End | Sessiya nomi fokusda bo'lsa — ro'yxatdagi keyingi sessiyaga o'tish |
| Enter | Fokusdagi sessiya terminalini ochish |

Terminal ustidagi tezkor tugmalar (Enter, y, n, Esc, Ctrl-C) pane'ga to'g'ridan-to'g'ri yuboriladi — ruxsat
so'rovlarini shu yerdan tasdiqlash mumkin.

**Tugagan sessiyalar.** Agent chiqqan pane «Tugagan» bo'limiga o'tadi (chiqish kodi bilan), terminali
ko'rish uchun ochiladi. `×` bitta pane'ni, **Tozalash** hammasini KanBot ro'yxatidan olib tashlaydi; ochiq
terminali yopiladi. Hali ishlayotgan pane olib tashlanmaydi. Suhbat tarixi o'chmaydi: sessiya «O'tgan
sessiyalar» dan davom ettiriladi.

**O'tgan sessiyalar.** Tanlangan loyihaning Claude va Codex sessiyalari (oxirgi 50 tasi), ular agentlarning
o'z transkript fayllaridan olinadi. Claude Code 30 kundan eski transkriptlarni o'zi o'chiradi
(`cleanupPeriodDays`), Codex o'chirmaydi. Keraksizlarini qo'lda o'chirish uchun bo'lim sarlavhasidagi
**Tanlash** ni bosing, sessiyalarni (yoki **Hammasi** ni) belgilang, **O'chirish** → **Butunlay o'chirish**:

- transkript fayli diskdan o'chadi: Claude — `~/.claude/projects/<papka>/<id>.jsonl` va yonidagi `<id>/`
  papka (subagent'lar, tool natijalari), Codex — `~/.codex/sessions/…/rollout-…-<id>.jsonl`;
- buni qaytarib bo'lmaydi, sessiyani endi davom ettirib ham bo'lmaydi;
- ochiq sessiya (jonli pane'da yoki oxirgi 45 s da yozilgan) tanlanmaydi;
- bittasi o'chirib bo'lmasa (ochilib qolgan, topilmagan), hech biri o'chirilmaydi.

## Yangilash

**Agent Hub** (kod yangilangandan keyin):

```sh
git pull
make sync
make install                                                  # frontend build, plist o'zgargan bo'lsa qayta yuklash
launchctl kickstart -k gui/$(id -u)/local.agent-hub.backend   # yangi Python kodini yuklash
```

Frontend fayllari diskdan beriladi, brauzer sahifasini yangilash yetadi. Backend'ni qayta ishga tushirish
agent sessiyalariga ta'sir qilmaydi.

**KanBot** yangilangandan keyin server va runner eski kod bilan ishlashda davom etadi, ularni qayta ishga
tushiring. Runner qayta ishga tushganda uning ichidagi barcha agent pane'lari to'xtaydi, avval ishlarni tugating:

```sh
uv tool upgrade kanbot
make install                                                        # venv yo'li o'zgargan bo'lsa plist yangilanadi
launchctl kickstart -k gui/$(id -u)/local.agent-hub.kanbot-server
launchctl kickstart -k gui/$(id -u)/local.agent-hub.kanbot-runner
make status
```

Agent Hub KanBot 0.8.x bilan tekshirilgan. Boshqa versiyada health `kanbot_version_unsupported` ogohlantirishini
ko'rsatadi: himoya launcher'i va API mosligini tekshirmasdan ishlatmang.

## Servislarni o'chirish

```sh
make uninstall
```

Servislar to'xtatiladi va `~/Library/LaunchAgents/local.agent-hub.*.plist` o'chiriladi. Loglar va
`~/.config/agent-hub` qoladi. Tirik agent pane'lari bo'lsa to'xtaydi va buyruq ogohlantiradi:
davom etish uchun `make uninstall FORCE=1`. Qayta ishga tushirish xavfsiz.

## Loglar

Servis loglari `~/Library/Logs/agent-hub/` da: `kanbot-server.log`, `kanbot-runner.log`, `backend.log`
(stdout va stderr bitta faylda).

```sh
make logs                 # oxirgi 50 qator va kuzatish (Ctrl-C)
make logs LOG_LINES=200
```

Loglar avtomatik aylantirilmaydi. Hajmi oshsa:

```sh
make logs-truncate        # har bir *.log joyida 0 baytga qisqartiriladi, bo'shatilgan hajm chiqariladi
```

Servislarni to'xtatish shart emas: launchd log faylini qo'shib yozish (`O_APPEND`) rejimida ochadi, keyingi
yozuvlar bo'sh faylning boshidan davom etadi. Faylni `rm` qilmang — servis o'chirilgan faylga yozishda davom
etadi va joy bo'shamaydi.

Servis ishga tushmasa: `make status`, keyin tegishli log. Tez-tez uchraydigan sabablar: port band
(`lsof -nP -iTCP:8787 -sTCP:LISTEN`), `.venv` yo'q (`make sync`), `kanbot` qayta o'rnatilgan (`make install`).

## Xavfsizlik

- Agent Hub va KanBot'da autentifikatsiya yo'q. Himoya faqat `127.0.0.1` ga bog'lanish va `Host`/`Origin`
  tekshiruviga tayanadi: begona saytdan kelgan brauzer so'rovlari 403 oladi. Portlarni tarmoqqa chiqarmang
  (`ssh -R`, ngrok, proxy, `0.0.0.0` ga ko'chirish). Mashinadagi har qanday lokal jarayon esa API'dan
  foydalana oladi.
- `kanbot server` ni himoyasiz, to'g'ridan-to'g'ri ishga tushirmang: KanBot'da CORS `*`.
- Runner faqat `--safe` rejimda: agentlarning auto-approve bayroqlari olib tashlanadi, ruxsat so'rovlarini
  pane terminalida (yoki tezkor tugmalar bilan) o'zingiz tasdiqlaysiz. `auto_approve` yoqilsa yoki `shell`, `glm`, `kimi`
  e'lon qilinsa, UI'da xato banneri va health'da `auto_approve_enabled` / `shell_enabled` chiqadi.
- Bir vaqtda faqat bitta runner: `kanbot up` yoki ikkinchi `kanbot runner` ni servislar bilan birga
  ishlatmang (`make status` buni tekshiradi).
- Agentlar sizning foydalanuvchi huquqlaringiz bilan loyiha papkalarida ishlaydi.
- Sessiyani o'chirishda fayl yo'li KanBot'dan keladi, lekin unga ishonilmaydi: fayl `CLAUDE_CONFIG_DIR`
  (yoki `~/.claude`)`/projects` yoki `~/.codex/sessions` ichida, `.jsonl` va nomi sessiya ID'siga mos
  bo'lishi shart (symlink'lar ochilib tekshiriladi). Boshqa runner mashinasidagi sessiya o'chirilmaydi.
- Papka brauzeri (`/api/folders`) faqat uy papkasi ichidagi papka nomlarini ko'rsatadi (symlink'lar ochilib
  tekshiriladi), fayllar va yashirin papkalar chiqmaydi.
- Plist'larda token va API kalitlari yo'q. KanBot tokeni faqat `~/.kanbot/config.json` da qoladi, runner uni
  o'zi o'qiydi. `claude` va `codex` obuna avtorizatsiyasidan foydalanadi.

## Dev-rejim (launchd servislarisiz)

Hammasini qo'lda, alohida terminallarda ishga tushirish (ishlab chiqish yoki servislarsiz sinash uchun).
launchd servislari o'rnatilgan bo'lsa, avval `make uninstall` qiling: portlar va runner to'qnashadi.
Avval bog'liqliklarni o'rnating:

```sh
make sync
```

1. **KanBot server** (1-terminal) — `127.0.0.1:8787`, himoya launcher'i orqali:

   ```sh
   make dev-kanbot
   ```

   `kanbot server` to'g'ridan-to'g'ri ishlatilmaydi. KanBot'da CORS `*` va autentifikatsiya yo'q, shu sabab
   brauzerdagi istalgan sayt agent ishga tushira olardi. `scripts/kanbot_guarded_server.py` KanBot
   ilovasini o'raydi va begona `Host` yoki `Origin` bilan kelgan HTTP/WebSocket so'rovlariga 403 qaytaradi.
   Runner, `kanbot` CLI, Agent Hub va KanBot'ning o'z UI'si (`http://127.0.0.1:8787`) ishlayveradi.

2. **KanBot runner** (2-terminal) — faqat SAFE rejimda (`--safe`, auto-approve yo'q):

   ```sh
   make dev-runner
   ```

   Runner `~/.kanbot/config.json` ga `auto_approve: false` ni yozadi. `kanbot up` ni bir vaqtda ishlatmang:
   ikkinchi runner paydo bo'ladi.

3. **Agent Hub** (3-terminal) — frontend'ni build qiladi va backend'ni `127.0.0.1:8700` da ishga tushiradi:

   ```sh
   make dev
   ```

   Port boshqa bo'lsa: `make dev AGENT_HUB_PORT=8711`. Birinchi ishga tushishda
   `~/.config/agent-hub/projects.yaml` Leveling loyihasi bilan yaratiladi.

4. **Frontend hot-reload** (ixtiyoriy, 4-terminal) — Vite `127.0.0.1:5173` da, `/api` va `/ws` so'rovlarini
   backend'ga yo'naltiradi:

   ```sh
   make dev-web
   ```

   Agent Hub begona `Host` yoki `Origin` bilan kelgan so'rovlarni 403 bilan rad etadi. `make dev` Vite
   manzilini (`http://127.0.0.1:5173`) `AGENT_HUB_EXTRA_ORIGINS` orqali faqat dev-rejimda ruxsat etadi.

Xavfli agentlar (`shell`, `glm`, `kimi`) o'chirilgan bo'lishi kerak:

```sh
kanbot config --disable shell glm kimi
```

`curl -s http://127.0.0.1:8700/api/health` da `ok: true` bo'lishi kerak. Runner `shell` ni e'lon qilsa yoki
auto-approve yoqilgan bo'lsa, `problems` da `shell_enabled` / `auto_approve_enabled` chiqadi.

To'xtatish: har bir terminalda `Ctrl-C`. Runner to'xtaganda uning ichidagi agent sessiyalari ham tugaydi.

## Sozlamalar

Agent Hub doim faqat `127.0.0.1` da tinglaydi. Qolgan qiymatlar env'dan, keyin
`~/.config/agent-hub/config.yaml` dan (ixtiyoriy), keyin default'dan olinadi:

| Env | `config.yaml` | Default |
|---|---|---|
| `AGENT_HUB_PORT` | `port` | `8700` |
| `AGENT_HUB_KANBOT_URL` | `kanbot_url` | `http://127.0.0.1:8787` (faqat loopback) |
| `AGENT_HUB_CONFIG_DIR` | — | `~/.config/agent-hub` |
| `AGENT_HUB_EXTRA_ORIGINS` | — | bo'sh (vergul bilan ajratilgan Origin'lar) |
| `AGENT_HUB_PROJECTS_ROOT` | `projects_root` | `~/my-projects` (papka takliflari shu yerdan) |
| `KANBOT_HOME` | — | `~/.kanbot` (faqat o'qiladi) |

Loyihalar `~/.config/agent-hub/projects.yaml` da saqlanadi (atomar yoziladi):

```yaml
projects:
- id: leveling
  name: Leveling
  backlog_dir: /Users/<siz>/my-projects/leveling-backend
  repos:
  - /Users/<siz>/my-projects/leveling-web
```

Loyiha papkalari — `backlog_dir` (har doim birinchi) va `repos` dagi qo'shimcha papkalar; `repos` bo'sh
bo'lishi mumkin. `repos` da `backlog_dir` yoki takror yozilgan bo'lsa, o'qishda e'tiborsiz qoldiriladi. `backlog_dir` da `.backlog/config.yml`, `backlog/config.yml`
yoki `backlog.config.yml` bo'lishi kerak.

## Tekshiruvlar

```sh
make check              # ruff, mypy --strict, pytest, vitest, eslint, tsc --noEmit
make test-integration   # haqiqiy backlog CLI bilan (vaqtinchalik papkada)
```
