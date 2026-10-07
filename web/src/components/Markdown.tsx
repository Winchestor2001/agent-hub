/** Markdown bloklarini React elementlariga aylantiradi: HTML ishlatilmaydi, matn qochiriladi. */

import type { ReactNode } from "react";

import { parseMarkdown } from "../config/markdown";

const INLINE_RE = /`([^`]+)`|\*\*(.+?)\*\*|\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g;

function renderInline(text: string): ReactNode[] {
  const out: ReactNode[] = [];
  let last = 0;
  for (const match of text.matchAll(INLINE_RE)) {
    const at = match.index;
    if (at > last) out.push(text.slice(last, at));
    const [whole, code, bold, label, href] = match;
    const key = `${String(at)}-${whole}`;
    if (code !== undefined) out.push(<code key={key}>{code}</code>);
    else if (bold !== undefined) out.push(<strong key={key}>{renderInline(bold)}</strong>);
    else if (label !== undefined && href !== undefined)
      out.push(
        <a key={key} href={href} target="_blank" rel="noreferrer noopener">
          {label}
        </a>,
      );
    last = at + whole.length;
  }
  if (last < text.length) out.push(text.slice(last));
  return out;
}

export function Markdown({ source }: { source: string }) {
  return (
    <div className="markdown">
      {parseMarkdown(source).map((block, index) => {
        const key = String(index);
        switch (block.type) {
          case "heading": {
            const Tag = block.level === 1 ? "h3" : block.level === 2 ? "h4" : "h5";
            return <Tag key={key}>{renderInline(block.text)}</Tag>;
          }
          case "paragraph":
            return <p key={key}>{renderInline(block.text)}</p>;
          case "quote":
            return <blockquote key={key}>{renderInline(block.text)}</blockquote>;
          case "code":
            return (
              <pre key={key} className="markdown-code">
                <code>{block.text}</code>
              </pre>
            );
          case "list": {
            const Tag = block.ordered ? "ol" : "ul";
            return (
              <Tag key={key}>
                {block.items.map((item, itemIndex) => (
                  <li key={String(itemIndex)} className={item.depth > 0 ? `markdown-depth-${String(item.depth)}` : undefined}>
                    {renderInline(item.text)}
                  </li>
                ))}
              </Tag>
            );
          }
          case "table":
            return (
              <div key={key} className="markdown-table">
                <table>
                  <thead>
                    <tr>
                      {block.head.map((cell, cellIndex) => (
                        <th key={String(cellIndex)}>{renderInline(cell)}</th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {block.rows.map((row, rowIndex) => (
                      <tr key={String(rowIndex)}>
                        {row.map((cell, cellIndex) => (
                          <td key={String(cellIndex)}>{renderInline(cell)}</td>
                        ))}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            );
        }
      })}
    </div>
  );
}
