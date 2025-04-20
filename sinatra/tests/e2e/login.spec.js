const { test, expect } = require('@playwright/test');

// Navigate to the login page before each test
test.describe('Login Page', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/login');
  });

  test('renders login form', async ({ page }) => {
    await expect(page.getByRole('heading', { name: /log in/i })).toBeVisible();
    await expect(page.locator('input[name="username"]')).toBeVisible();
    await expect(page.locator('input[name="password"]')).toBeVisible();
    await expect(page.getByRole('button', { name: /log in/i })).toBeVisible();
  });

  test('shows error on invalid credentials', async ({ page }) => {
    await page.fill('input[name="username"]', 'wronguser');
    await page.fill('input[name="password"]', 'badpass');
    await page.click('input[type="submit"]');
    await expect(page.locator('.error')).toContainText(/error/i);
  });

  // Requires seeded user: username 'test', password '123'
  test('allows successful login', async ({ page }) => {
    await page.fill('input[name="username"]', 'test');
    await page.fill('input[name="password"]', '123');
    await page.click('input[type="submit"]');

    // Verify redirect to home
    expect(page.url()).toBe('/');
    await expect(page.getByText('You were successfully logged in.')).toBeVisible();
  });
});
