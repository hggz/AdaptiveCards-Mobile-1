import { test, expect } from "@playwright/test";

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
    await expect(page.locator("#ac-status")).toContainText("wasm loaded", {
      timeout: 30_000,
    });
    await page.selectOption("#ac-card-picker", card);
    await expect(page.locator("#ac-status")).toContainText(card, {
      timeout: 10_000,
    });
    // Wait until the AdaptiveCard component finishes its async render
    // (the "loading…" placeholder disappears once IR is in hand).
    await expect(page.locator("#ac-card-mount .ac-status")).toHaveCount(0, {
      timeout: 30_000,
    });
    const html = await page.locator("#ac-card-mount").innerHTML();
    expect(html).toMatchSnapshot(`${card}.html`);
  });
}
