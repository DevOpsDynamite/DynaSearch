const { test, expect } = require('@playwright/test');

test.describe('Weather Endpoint', () => {
  test('JSON API returns valid forecast or error', async ({ request }) => {
    const response = await request.get('/api/weather');
    // API should respond with either 200 (OK) or 503 (Service Unavailable)
    const status = response.status();
    expect([200, 503]).toContain(status);

    const body = await response.json();
    if (response.ok()) {
      // Expect city name + forecast data
      expect(body).toHaveProperty('city_name');
      expect(body).toHaveProperty('data');
      expect(Array.isArray(body.data)).toBe(true);
      expect(body.data.length).toBeGreaterThan(0);
    } else {
      // Error response should include status: 'error' and a message
      expect(body).toHaveProperty('status', 'error');
      expect(body).toHaveProperty('message');
      expect(typeof body.message).toBe('string');
    }
  });

  test('UI weather page renders forecast or error', async ({ page }) => {
    await page.goto('/weather');

    // Heading should start with '7-Day Weather Forecast for'
    await expect(
      page.getByRole('heading', { name: /^7-Day Weather Forecast for/ })
    ).toBeVisible();

    // Check if error message is shown
    if (await page.locator('p:has-text("Error:")').count() > 0) {
      await expect(page.locator('p')).toContainText('Error:');
    } else {
      // Otherwise, assert there is at least one forecast item
      const itemCount = await page.locator('ul li').count();
      expect(itemCount).toBeGreaterThan(0); 
    }
  });
});
