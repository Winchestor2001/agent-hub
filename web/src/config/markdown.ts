/**
 * Qo'llanmalar uchun kichik markdown parser: sarlavha, paragraf, ro'yxat, kod bloki, jadval, iqtibos.
 * Inline belgilash (`kod`, **qalin**, havola) — `components/Markdown.tsx` da.
 */

export type Block =
  | { type: "heading"; level: number; text: string }
  | { type: "paragraph"; text: string }
  | { type: "list"; ordered: boolean; items: { text: string; depth: number }[] }
  | { type: "code"; lang: string; text: string }
  | { type: "table"; head: string[]; rows: string[][] }
  | { type: "quote"; text: string };

const LIST_RE = /^(\s*)([-*]|\d+\.)\s+(.*)$/;

function tableCells(line: string): string[] {
  return line
    .trim()
    .replace(/^\|/, "")
    .replace(/\|$/, "")
    .split("|")
    .map((cell) => cell.trim());
}

export function parseMarkdown(source: string): Block[] {
  const lines = source.replace(/\r\n/g, "\n").split("\n");
  const blocks: Block[] = [];
  let index = 0;
  const peek = () => lines[index] ?? "";

  while (index < lines.length) {
    const line = peek();
    if (line.trim() === "") {
      index++;
      continue;
    }
    const fence = /^```(\S*)/.exec(line);
    if (fence) {
      index++;
      const code: string[] = [];
      while (index < lines.length && !peek().startsWith("```")) code.push(lines[index++] ?? "");
      index++; // yopuvchi ```
      blocks.push({ type: "code", lang: fence[1] ?? "", text: code.join("\n") });
      continue;
    }
    const heading = /^(#{1,4})\s+(.*)$/.exec(line);
    if (heading) {
      blocks.push({ type: "heading", level: heading[1]?.length ?? 1, text: heading[2] ?? "" });
      index++;
      continue;
    }
    if (line.trimStart().startsWith("|")) {
      const rows: string[][] = [];
      while (index < lines.length && peek().trimStart().startsWith("|")) rows.push(tableCells(lines[index++] ?? ""));
      const [head = [], ...rest] = rows;
      // Ikkinchi qator — `| --- |` ajratgich.
      const body = rest.length > 0 && rest[0]?.every((cell) => /^:?-+:?$/.test(cell)) ? rest.slice(1) : rest;
      blocks.push({ type: "table", head, rows: body });
      continue;
    }
    if (line.startsWith(">")) {
      const quote: string[] = [];
      while (index < lines.length && peek().startsWith(">")) quote.push((lines[index++] ?? "").replace(/^>\s?/, ""));
      blocks.push({ type: "quote", text: quote.join(" ") });
      continue;
    }
    const first = LIST_RE.exec(line);
    if (first) {
      const ordered = /\d/.test(first[2] ?? "");
      const items: { text: string; depth: number }[] = [];
      while (index < lines.length) {
        const match = LIST_RE.exec(peek());
        const depth = Math.min(3, Math.floor((match?.[1]?.length ?? 0) / 2));
        if (match && depth === 0 && /\d/.test(match[2] ?? "") !== ordered) break;
        if (match) {
          items.push({ text: match[3] ?? "", depth });
        } else if (/^\s{2,}\S/.test(peek()) && items.length > 0) {
          // Davom etuvchi qator — oldingi bandga qo'shiladi.
          const last = items[items.length - 1];
          if (last) last.text += ` ${peek().trim()}`;
        } else {
          break;
        }
        index++;
      }
      blocks.push({ type: "list", ordered, items });
      continue;
    }
    const paragraph: string[] = [];
    while (index < lines.length) {
      const next = peek();
      if (next.trim() === "" || /^(#{1,4}\s|```|\||>)/.test(next.trimStart()) || LIST_RE.test(next)) break;
      paragraph.push(next.trim());
      index++;
    }
    blocks.push({ type: "paragraph", text: paragraph.join(" ") });
  }
  return blocks;
}
