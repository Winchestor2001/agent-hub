# Hook'lar

Hook — Claude ma'lum hodisada (vosita ishlatishdan oldin/keyin, prompt yuborilganda, to'xtaganda) ishga tushiradigan buyruq. Ikki qismdan iborat:

1. **Skript** — `hooks/<nom>.sh` (yoki `.js`, `.py`). Agent Hub yangi skriptni bajariladigan (0755) qilib yaratadi.
2. **Ro'yxatdan o'tkazish** — settings.json'ning `hooks` bo'limi. Skriptning o'zi bu qadamsiz ishlamaydi.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/guard-bash.sh" }
        ]
      }
    ]
  }
}
```

## Skript qanday ishlaydi
- Hodisa ma'lumoti JSON sifatida **stdin** orqali keladi (masalan, `tool_input.command`).
- Chiqish kodi `0` — davom etish; `2` — bloklash, stderr matni Claude'ga ko'rsatiladi.
- Asosiy hodisalar: `PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `Stop`, `SessionStart`, `Notification`.

## Qamrov
- Global: skript `~/.claude/hooks/`, ro'yxat `~/.claude/settings.json` da — barcha loyihalarda ishlaydi.
- Loyiha: skript `.claude/hooks/`, ro'yxat `.claude/settings.json` da; yo'lni `$CLAUDE_PROJECT_DIR` bilan yozing.

## Ehtiyot bo'ling
Hook sizning huquqlaringiz bilan har qanday buyruqni bajaradi. Faqat o'zingiz tushunadigan skriptlarni qo'shing.
