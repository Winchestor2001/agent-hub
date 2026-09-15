import { useEffect, useState } from "react";

interface Health {
  ok: boolean;
  version: string;
}

export function App() {
  const [health, setHealth] = useState<Health | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetch("/api/health")
      .then(async (resp) => {
        if (!resp.ok) throw new Error(`HTTP ${String(resp.status)}`);
        setHealth((await resp.json()) as Health);
      })
      .catch((err: unknown) => {
        setError(err instanceof Error ? err.message : String(err));
      });
  }, []);

  return (
    <main className="shell">
      <h1>Agent Hub</h1>
      {health && <p>backend v{health.version}</p>}
      {error && <p className="error">Backend bilan aloqa yo'q: {error}</p>}
    </main>
  );
}
