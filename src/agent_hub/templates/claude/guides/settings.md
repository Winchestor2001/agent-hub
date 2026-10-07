# Settings (settings.json)

Sozlamalar JSON fayllarda: ruxsatlar, muhit o'zgaruvchilari, hook'lar, model va boshqalar.

| Fayl | Qamrov | Git |
| --- | --- | --- |
| `~/.claude/settings.json` | user — barcha loyihalar | — |
| `.claude/settings.json` | project — jamoa | qo'shiladi |
| `.claude/settings.local.json` | local — faqat siz | qo'shilmaydi |

## Ustuvorlik

**local > project > user**: `settings.local.json` > `.claude/settings.json` > `~/.claude/settings.json`. Bir xil kalit bo'lsa yuqoridagisi ustun; `permissions.allow` kabi ro'yxatlar birlashtiriladi. (Tashkilot "managed" sozlamalari hammasidan ustun.)

## Misol

```json
{
  "permissions": {
    "allow": ["Bash(npm run test:*)"],
    "deny": ["Read(./.env)"]
  },
  "env": { "NODE_ENV": "development" }
}
```

- Fayl to'g'ri JSON obyekt bo'lishi shart — Agent Hub xato qatorini ko'rsatadi.
- `hooks` bo'limi obyekt bo'lishi kerak (qarang: "Hook'lar" qo'llanmasi).
- `/model` buyrug'i tanlovni user settings'dagi `model` kalitiga yozadi.
