# Subagentlar

Subagent — alohida kontekstda ishlaydigan yordamchi (masalan, kod ko'rib chiquvchi). Fayl: `agents/<nom>.md`.

```markdown
---
name: reviewer
description: Kod o'zgarishlarini xato va xavfsizlik bo'yicha ko'rib chiqadi. Commit oldidan chaqiriladi.
tools: Read, Grep, Glob
model: inherit
---

Sen tajribali reviewer'san...
```

- `name` va `description` majburiy. `tools` bo'lmasa agent barcha vositalarni oladi — keragini aniq yozing.
- `model`: `inherit` (sessiya modeli), `sonnet`, `opus`, `haiku` yoki to'liq model ID.

## Qamrov

- **Global** — `~/.claude/agents/` — barcha loyihalarda.
- **Loyiha** — `.claude/agents/` — faqat shu loyihada.
- **Bir nechta loyiha** — "Qo'llash" bilan har loyihaga nusxa.

## Ustuvorlik

Bir xil nomli agent ikki joyda bo'lsa **Project (loyiha) ustun**: loyiha agenti global agentni yopadi. Bu skill'larning teskarisi — Agent Hub ikkala holatda ham ogohlantiradi.
