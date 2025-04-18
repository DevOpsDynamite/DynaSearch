const { test, expect } = require('@playwright/test');

test('about page shows mission', async ({ page }) => {
  await page.goto('/about');
  await expect(page).toHaveTitle('DynaSearch 🧨');
  await expect(page.getByRole('heading', { name: 'Our mission' })).toBeVisible();
  await expect(page.locator('p')).toContainText("We intend to build the world's best search engine!");
});