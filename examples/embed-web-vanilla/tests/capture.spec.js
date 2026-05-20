import { test } from "@playwright/test";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
// `examples/embed-web-vanilla/tests/` -> repo root.
const REPO_ROOT = path.resolve(__dirname, "..", "..", "..");
const OUT_DIR = path.join(REPO_ROOT, "docs", "web-host-screenshots");

const CARDS = [
  "simple-text.json",
  "containers.json",
  "input-form.json",
  "all-actions.json",
  "table.json",
  "rating.json",
  "edge-empty-card.json",
  "windows-extras.json",
];

for (const card of CARDS) {
  test(`capture ${card}`, async ({ page }) => {
    test.setTimeout(120_000);
    await page.goto("/");
    await page.locator("#ac-status").waitFor({ state: "visible" });
    // Initial render completes once status reads "<card> — rendered".
    await page.waitForFunction(
      () =>
        document
          .querySelector("#ac-status")
          ?.textContent?.includes("rendered") === true,
      null,
      { timeout: 60_000 }
    );
    await page.selectOption("#ac-card-picker", card);
    await page.waitForFunction(
      (c) => {
        const t = document.querySelector("#ac-status")?.textContent ?? "";
        return t.includes(c) && t.includes("rendered");
      },
      card,
      { timeout: 60_000 }
    );
    // Settle: give the browser a frame to paint anything async (image
    // loads, font fallback) before screenshotting.
    await page.waitForTimeout(250);
    const out = path.join(OUT_DIR, card.replace(/\.json$/, "") + ".png");
    await page.locator("#ac-card-mount").screenshot({
      path: out,
      omitBackground: false,
    });
    console.log(`captured -> ${out}`);
  });
}
