# Qoidalar (rules)

`rules/*.md` — CLAUDE.md'ni mavzular bo'yicha bo'lib yozish usuli: har fayl bitta mavzu (kod uslubi, testlar, API).

```markdown
---
paths:
  - "src/api/**"
---

# API qoidalari
- Har endpoint uchun test yozing.
```

- `paths` bo'lsa qoida faqat shu fayllar bilan ishlaganda yuklanadi; bo'lmasa — har doim.
- Global: `~/.claude/rules/` (hamma loyiha), loyiha: `.claude/rules/`.
