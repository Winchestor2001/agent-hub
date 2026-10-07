# Umumiy: Claude Code konfiguratsiyasi qayerda yashaydi

Claude Code sozlamalari ikki darajada turadi:

- **Global (shaxsiy)** — `~/.claude/` papkasi. Bu yerdagi narsa sizning **barcha loyihalaringizda** ishlaydi.
- **Loyiha** — loyiha papkasi (`CLAUDE.md`, `.mcp.json`, `.claude/`). Faqat **shu loyihada** ishlaydi va odatda git orqali jamoa bilan bo'lishiladi.

Ikkalasi ixtiyoriy: faqat global, faqat loyiha yoki ikkalasini ham ishlatishingiz mumkin.

## Fayllar xaritasi

| Tur | Global | Loyiha |
| --- | --- | --- |
| Yo'riqnoma | `~/.claude/CLAUDE.md` | `CLAUDE.md`, shaxsiy: `CLAUDE.local.md` |
| Sozlamalar | `~/.claude/settings.json` | `.claude/settings.json`, shaxsiy: `.claude/settings.local.json` |
| MCP serverlar | Agent Hub'da yo'q (`claude mcp add --scope user`) | `.mcp.json` |
| Qoidalar | `~/.claude/rules/*.md` | `.claude/rules/*.md` |
| Buyruqlar | `~/.claude/commands/*.md` | `.claude/commands/*.md` |
| Skill'lar | `~/.claude/skills/<nom>/SKILL.md` | `.claude/skills/<nom>/SKILL.md` |
| Subagentlar | `~/.claude/agents/*.md` | `.claude/agents/*.md` |
| Hook skriptlari | `~/.claude/hooks/` | `.claude/hooks/` |

## Ustuvorlik (bir xil narsa ikki joyda bo'lsa)

- **Skill**: Personal (global) ustun — global skill bir xil nomli loyiha skill'ini **yopadi**.
- **Subagent**: Project (loyiha) ustun — loyihadagi agent global agentni yopadi.
- **Settings**: local > project > user, ya'ni `.claude/settings.local.json` > `.claude/settings.json` > `~/.claude/settings.json`. Ro'yxatlar (masalan `permissions.allow`) birlashtiriladi.
- **CLAUDE.md**: hammasi birga yuklanadi (global + loyiha + local). Aniqroq (loyiha) yo'riqnoma keyin o'qiladi.

## Bitta, bir nechta yoki barcha loyihalar

- **Barcha loyihalar** — globalga yozing.
- **Bitta loyiha** — shu loyiha qamrovini tanlab yozing.
- **Bir nechta loyiha** — Agent Hub'dagi **"Qo'llash"** tugmasi: bitta matn tanlangan loyihalarning har biriga alohida nusxa sifatida yoziladi. Keyin o'zgartirsangiz, har nusxani alohida yangilang (yoki qayta qo'llang).

## Xavfsizlik

- Agent Hub yozishdan oldin eski nusxani `~/.config/agent-hub/config-backups/` ga saqlaydi.
- Fayl boshqa joyda o'zgargan bo'lsa saqlash rad etiladi — qayta yuklab, o'zgarishni qayta kiriting.
- Agent Hub hech narsani commit qilmaydi: loyiha fayllarini git'ga o'zingiz qo'shasiz.
- Settings va hook'lar kompyuteringizda buyruq ishga tushiradi: notanish manbadan nusxalamang.
