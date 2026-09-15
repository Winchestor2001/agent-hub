import type { ReactNode } from "react";

interface PanelProps {
  title: string;
  /** Sarlavha o'ng tomonidagi qo'shimcha (hisoblagich, tugma). */
  aside?: ReactNode;
  className?: string;
  children: ReactNode;
}

export function Panel({ title, aside, className, children }: PanelProps) {
  return (
    <section className={className ? `panel ${className}` : "panel"} aria-label={title}>
      <header className="panel-header">
        <h2>{title}</h2>
        {aside}
      </header>
      <div className="panel-body">{children}</div>
    </section>
  );
}
