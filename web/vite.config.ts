import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

const backend = `http://127.0.0.1:${process.env.AGENT_HUB_PORT ?? "8700"}`;

export default defineConfig({
  plugins: [react()],
  build: {
    outDir: "../src/agent_hub/static",
    emptyOutDir: true,
  },
  server: {
    host: "127.0.0.1",
    port: 5173,
    strictPort: true,
    proxy: {
      "/api": { target: backend },
      "/ws": { target: backend, ws: true },
    },
  },
});
