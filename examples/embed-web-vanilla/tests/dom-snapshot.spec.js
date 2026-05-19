/**
 * wasm-port: DOM-snapshot gate. Loads the host page, selects each
 * reference card in turn, waits for the mount to populate, and diffs
 * the serialized mount HTML against the committed baseline in
 * `baselines/<card>.html`.
 *
 * On first run (or after deliberate IR / renderer changes), regenerate
 * with `npm run test -- --update-snapshots`; commit the resulting
 * baselines under `baselines/`.
 *
 * This is the wasm-port analogue of windows-port's
 * `windows-render-smoke` pixel-diff gate; here we compare structured
 * DOM rather than pixels because:
 *   1. Browser font / antialias rendering varies per-runner-OS, so
 *      pixel diffs are noisy without per-OS baselines.
 *   2. The IR contract is already what we want to assert on — pixel
 *      diff doesn't add information beyond "the renderer + walker
 *      both still produce the same DOM for the same IR".
 */
import { test, expect } from "@playwright/test";
import { readFile } from "node:fs/promises";

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
  test(`DOM snapshot — ${card}`, async ({ page }) => {
    await page.goto("/");

    // Wait for the wasm boot to settle.
    await expect(page.locator("#ac-status")).toContainText("rendered", {
      timeout: 30_000,
    });

    await page.selectOption("#ac-card-picker", card);
    await expect(page.locator("#ac-status")).toContainText(card, {
      timeout: 10_000,
    });
    await expect(page.locator("#ac-status")).toContainText("rendered", {
      timeout: 30_000,
    });

    const html = await page.locator("#ac-card-mount").innerHTML();
    expect(html).toMatchSnapshot(`${card}.html`);
  });
}
