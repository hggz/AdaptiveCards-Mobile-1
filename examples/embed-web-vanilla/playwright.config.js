import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./tests",
  // Vite dev server boots on :5173 by default; reuse it across runs
  // when one is already up.
  webServer: {
    command: "npm run dev -- --port 5173 --strictPort",
    url: "http://localhost:5173",
    reuseExistingServer: true,
    timeout: 60_000,
  },
  use: {
    baseURL: "http://localhost:5173",
    headless: true,
  },
  // Single Chromium project for now; cross-browser parity is parked
  // until the gate is stable.
  projects: [
    {
      name: "chromium",
      use: { browserName: "chromium" },
    },
  ],
});
