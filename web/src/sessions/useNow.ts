import { useEffect, useState } from "react";

/** Joriy vaqt (unix soniya) — nisbiy vaqtlar ma'lumot o'zgarmasa ham yangilanib turadi. */
export function useNow(intervalMs = 5000): number {
  const [now, setNow] = useState(() => Date.now() / 1000);
  useEffect(() => {
    const id = window.setInterval(() => {
      setNow(Date.now() / 1000);
    }, intervalMs);
    return () => {
      window.clearInterval(id);
    };
  }, [intervalMs]);
  return now;
}
