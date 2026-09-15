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

1. **KanBot server** (1-terminal) — `127.0.0.1:8787`:

   ```sh
   make dev-kanbot
   ```

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

   Port boshqa bo'lsa: `make dev AGENT_HUB_PORT=8711`.

4. **Frontend hot-reload** (ixtiyoriy, 4-terminal) — Vite `127.0.0.1:5173` da, `/api` va `/ws` so'rovlarini
   backend'ga yo'naltiradi:

   ```sh
   make dev-web
   ```

To'xtatish: har bir terminalda `Ctrl-C`. Runner to'xtaganda uning ichidagi agent sessiyalari ham tugaydi.

## Tekshiruvlar

```sh
make check              # ruff, mypy --strict, pytest, eslint, tsc --noEmit
make test-integration   # haqiqiy backlog CLI bilan (vaqtinchalik papkada)
```
