const { test, expect } = require('@playwright/test');

// Navigate to the home page before each test
test.beforeEach(async ({ page }) => {
  await page.goto('/');
});

const SEARCH_TERMS = {
  valid: 'JavaScript',
  invalid: 'unlikely_term_xyz'
};


test.describe('Search Functionality', () => {
  test('should return results for a valid search term', async ({ page }) => {
    // Search for a valid term
    const input = page.getByPlaceholder('Search...');
    await input.fill(SEARCH_TERMS.valid);
    await input.press('Enter');

    // Check the URL has the query param
    const currentUrl = page.url();
    expect(currentUrl).toContain(`?q=${SEARCH_TERMS.valid}`);

    // Expect at least one result title containing the term
    const titles = await page.locator('.search-result-title').allTextContents();
    expect(titles.length).toBeGreaterThan(0);
    expect(
      titles.some(t => t.toLowerCase().includes(SEARCH_TERMS.valid.toLowerCase()))
    ).toBeTruthy();
  });

  test('should show no results for an unlikely search term', async ({ page }) => {
    // Search for a nonsense term
    const input = page.getByPlaceholder('Search...');
    await input.fill(SEARCH_TERMS.invalid);
    await input.press('Enter');

    // Check the URL updates with the search term
    expect(page.url()).toContain(`?q=${SEARCH_TERMS.invalid}`);

    // Check the URL updates with the search term
    await expect(page.locator('.search-result-title')).toHaveCount(0);
    await expect(page.locator('#results')).toBeEmpty();
  });
});