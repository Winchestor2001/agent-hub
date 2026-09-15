# Agent Hub

Claude Code va Codex sessiyalari (KanBot orqali) hamda Backlog.md vazifalari uchun lokal veb UI.
Bitta jarayon, bitta port: `http://127.0.0.1:8700`. Hammasi faqat `127.0.0.1` da tinglaydi.
Ilova telemetriya yubormaydi va tashqi so'rov qilmaydi.

> README qoralama holatda: to'liq o'rnatish (launchd), loyiha qo'shish va loglar bo'limlari
> TASK-15 da yoziladi.

## Talablar

- macOS, Python 3.12, [uv](https://docs.astral.sh/uv/), Node.js 24 + npm
- [KanBot](https://pypi.org/project/kanbot/) 0.8.x (`uv tool install kanbot`)
- [Backlog.md](https://github.com/MrLesk/Backlog.md) CLI (`backlog`)
- `claude` va/yoki `codex` CLI (obuna orqali avtorizatsiya qilingan; API kalitlari kerak emas)

## Dev-rejim (launchd servislarisiz)

launchd servislarini o'rnatishdan oldin hammasini qo'lda, alohida terminallarda ishga tushirish mumkin.
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
| `KANBOT_HOME` | — | `~/.kanbot` (faqat o'qiladi) |

Loyihalar `~/.config/agent-hub/projects.yaml` da saqlanadi (atomar yoziladi):

```yaml
projects:
- id: leveling
  name: Leveling
  backlog_dir: /Users/<siz>/my-projects/leveling-backend
  repos:
  - /Users/<siz>/my-projects/leveling-backend
```

`repos` bo'sh bo'lsa `backlog_dir` olinadi. `backlog_dir` da `.backlog/config.yml`, `backlog/config.yml`
yoki `backlog.config.yml` bo'lishi kerak.

## Tekshiruvlar

```sh
make check              # ruff, mypy --strict, pytest, vitest, eslint, tsc --noEmit
make test-integration   # haqiqiy backlog CLI bilan (vaqtinchalik papkada)
```
