import { createContext, useContext } from "react";

import { createTranslator, DEFAULT_LOCALE, type Translator } from "./messages";

export const I18nContext = createContext<Translator>(createTranslator(DEFAULT_LOCALE));

export function useI18n(): Translator {
  return useContext(I18nContext);
}
