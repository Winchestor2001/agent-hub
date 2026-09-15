import { useEffect, useMemo, type ReactNode } from "react";

import { I18nContext } from "./context";
import { createTranslator, type Locale } from "./messages";

export function I18nProvider({ locale, children }: { locale: Locale; children: ReactNode }) {
  const translator = useMemo(() => createTranslator(locale), [locale]);

  useEffect(() => {
    document.documentElement.lang = locale;
  }, [locale]);

  return <I18nContext value={translator}>{children}</I18nContext>;
}
