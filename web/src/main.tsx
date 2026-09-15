import { QueryClientProvider } from "@tanstack/react-query";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";

import { App } from "./App";
import { createQueryClient } from "./api/queries";
import { I18nProvider } from "./i18n/I18nProvider";
import { DEFAULT_LOCALE } from "./i18n/messages";
import "./styles.css";

const root = document.getElementById("root");
if (!root) {
  throw new Error("#root topilmadi");
}

createRoot(root).render(
  <StrictMode>
    <QueryClientProvider client={createQueryClient()}>
      <I18nProvider locale={DEFAULT_LOCALE}>
        <App />
      </I18nProvider>
    </QueryClientProvider>
  </StrictMode>,
);
