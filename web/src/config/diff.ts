/** Saqlashdan oldin ko'rsatiladigan qator diff (LCS, bog'liqliksiz). */

export type DiffOp = "same" | "add" | "del";

export interface DiffLine {
  op: DiffOp;
  text: string;
  /** Eski/yangi fayldagi qator raqami (1 dan); yo'q tomonda `null`. */
  oldNo: number | null;
  newNo: number | null;
}

/** Kontekst bilan ko'rsatiladigan qatorlar yoki tashlab ketilgan oraliq. */
export type DiffRow = DiffLine | { op: "skip"; count: number };

/** O'rta qism shundan katta bo'lsa LCS jadvali o'rniga «hammasi o'chdi + hammasi qo'shildi». */
const MAX_CELLS = 4_000_000;

function splitLines(text: string): string[] {
  if (text === "") return [];
  const lines = text.split("\n");
  // Oxirgi "\n" alohida bo'sh qator emas.
  if (lines.at(-1) === "") lines.pop();
  return lines;
}

export function diffLines(before: string, after: string): DiffLine[] {
  const a = splitLines(before);
  const b = splitLines(after);
  const lineA = (index: number) => a[index] ?? "";
  const lineB = (index: number) => b[index] ?? "";
  let start = 0;
  while (start < a.length && start < b.length && lineA(start) === lineB(start)) start++;
  let endA = a.length;
  let endB = b.length;
  while (endA > start && endB > start && lineA(endA - 1) === lineB(endB - 1)) {
    endA--;
    endB--;
  }

  const out: DiffLine[] = [];
  for (let i = 0; i < start; i++) out.push({ op: "same", text: lineA(i), oldNo: i + 1, newNo: i + 1 });

  const n = endA - start;
  const m = endB - start;
  if (n * m > MAX_CELLS) {
    for (let i = start; i < endA; i++) out.push({ op: "del", text: lineA(i), oldNo: i + 1, newNo: null });
    for (let j = start; j < endB; j++) out.push({ op: "add", text: lineB(j), oldNo: null, newNo: j + 1 });
  } else {
    // lcs(i, j) — a[start+i..], b[start+j..] uchun eng uzun umumiy qism uzunligi.
    const width = m + 1;
    const table = new Uint32Array((n + 1) * width);
    const lcs = (i: number, j: number) => table[i * width + j] ?? 0;
    for (let i = n - 1; i >= 0; i--) {
      for (let j = m - 1; j >= 0; j--) {
        table[i * width + j] =
          lineA(start + i) === lineB(start + j) ? lcs(i + 1, j + 1) + 1 : Math.max(lcs(i + 1, j), lcs(i, j + 1));
      }
    }
    let i = 0;
    let j = 0;
    while (i < n || j < m) {
      if (i < n && j < m && lineA(start + i) === lineB(start + j)) {
        out.push({ op: "same", text: lineA(start + i), oldNo: start + i + 1, newNo: start + j + 1 });
        i++;
        j++;
      } else if (i < n && (j === m || lcs(i + 1, j) >= lcs(i, j + 1))) {
        // Teng bo'lsa avval o'chirilgan qator (odatiy unified diff tartibi).
        out.push({ op: "del", text: lineA(start + i), oldNo: start + i + 1, newNo: null });
        i++;
      } else {
        out.push({ op: "add", text: lineB(start + j), oldNo: null, newNo: start + j + 1 });
        j++;
      }
    }
  }

  for (let k = 0; k < a.length - endA; k++) {
    out.push({ op: "same", text: lineA(endA + k), oldNo: endA + k + 1, newNo: endB + k + 1 });
  }
  return out;
}

/** O'zgarishlar atrofida `context` qator qoldiradi, qolganini `skip` bilan qisqartiradi. */
export function withContext(lines: DiffLine[], context = 3): DiffRow[] {
  const keep = new Array<boolean>(lines.length).fill(false);
  lines.forEach((line, index) => {
    if (line.op === "same") return;
    for (let k = Math.max(0, index - context); k <= Math.min(lines.length - 1, index + context); k++) keep[k] = true;
  });
  const rows: DiffRow[] = [];
  let skipped = 0;
  lines.forEach((line, index) => {
    if (keep[index]) {
      if (skipped > 0) rows.push({ op: "skip", count: skipped });
      skipped = 0;
      rows.push(line);
    } else {
      skipped++;
    }
  });
  if (skipped > 0) rows.push({ op: "skip", count: skipped });
  return rows;
}

export function diffStats(lines: DiffLine[]): { added: number; removed: number } {
  let added = 0;
  let removed = 0;
  for (const line of lines) {
    if (line.op === "add") added++;
    else if (line.op === "del") removed++;
  }
  return { added, removed };
}
