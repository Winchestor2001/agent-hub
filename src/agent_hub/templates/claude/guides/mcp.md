# MCP serverlar (.mcp.json)

`.mcp.json` — loyiha papkasida turadi va loyiha uchun MCP serverlarini (tashqi vositalar) ulaydi. Git'ga qo'shilsa jamoa ham oladi; Claude birinchi ishlatishda tasdiq so'raydi.

```json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": { "GITHUB_TOKEN": "${GITHUB_TOKEN}" }
    }
  }
}
```

- `mcpServers` obyekt bo'lishi shart; har kalit — server nomi.
- Tokenlarni faylga to'g'ridan-to'g'ri yozmang: `${O'ZGARUVCHI}` ko'rinishida muhitdan oling.
- HTTP server: `{ "type": "http", "url": "https://..." }`.

## Global MCP

Barcha loyihalar uchun MCP Agent Hub orqali tahrirlanmaydi: u `~/.claude.json` da saqlanadi va bu Claude'ning jonli holat fayli. Terminalda qo'shing:

```
claude mcp add --scope user <nom> -- <buyruq>
```
