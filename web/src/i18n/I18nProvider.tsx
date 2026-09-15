import { useEffect, useMemo, useState, type ReactNode } from "react";

import { I18nContext, type I18n } from "./context";
import { createTranslator, readLocale, writeLocale, type Locale } from "./messages";

function browserStorage(): Storage | null {
  try {
    return window.localStorage;
  } catch {
    return null;
  }
}

/** Til brauzerda saqlanadi — sahifa qayta yuklanganda ham tanlov qoladi. */
export function I18nProvider({ children }: { children: ReactNode }) {
  const [locale, setLocaleState] = useState<Locale>(() => readLocale(browserStorage()));

  const value = useMemo<I18n>(
    () => ({
      ...createTranslator(locale),
      setLocale: (next) => {
        writeLocale(browserStorage(), next);
        setLocaleState(next);
      },
    }),
    [locale],
  );

  useEffect(() => {
    document.documentElement.lang = locale;
  }, [locale]);

  return <I18nContext value={value}>{children}</I18nContext>;
}
