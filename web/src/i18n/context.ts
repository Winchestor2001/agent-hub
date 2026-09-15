import { createContext, useContext } from "react";

import { createTranslator, DEFAULT_LOCALE, type Locale, type Translator } from "./messages";

export interface I18n extends Translator {
  setLocale: (locale: Locale) => void;
}

export const I18nContext = createContext<I18n>({
  ...createTranslator(DEFAULT_LOCALE),
  setLocale: () => undefined,
});

export function useI18n(): I18n {
  return useContext(I18nContext);
}
