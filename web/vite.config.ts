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
      // changeOrigin: Host backend manziliga almashtiriladi (Agent Hub Host'ni tekshiradi).
      // Origin o'zgartirilmaydi — `make dev` 5173 ni AGENT_HUB_EXTRA_ORIGINS ga qo'shadi.
      "/api": { target: backend, changeOrigin: true },
      "/ws": { target: backend, ws: true, changeOrigin: true },
    },
  },
});
