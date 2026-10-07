# Buyruqlar (slash commands)

`commands/<nom>.md` fayli `/nom` buyrug'ini yaratadi. Fayl matni — Claude'ga yuboriladigan prompt.

```markdown
---
description: O'zgarishlarni ko'rib chiqib commit xabarini taklif qiladi
argument-hint: "[qisqa izoh]"
---

Git diff'ni o'qing va commit xabarini yozing. Qo'shimcha: $ARGUMENTS
```

- Frontmatter ixtiyoriy; `description` menyuda ko'rinadi.
- `$ARGUMENTS` — buyruqdan keyin yozilgan matn (`/ship tezkor tuzatish`).
- Global (`~/.claude/commands/`) — hamma loyihada; loyiha (`.claude/commands/`) — faqat shu loyihada.
- Ko'p qadamli yoki fayllar bilan ishlaydigan narsa uchun skill qulayroq.
