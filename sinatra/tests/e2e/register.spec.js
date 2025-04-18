const { test, expect } = require('@playwright/test');

test.describe('Registration Page', () => {
    test.beforeEach(async ({ page }) => {
        await page.goto('/register');
      });

  test('renders registration form correctly', async ({ page }) => {
    // Check heading/form title
    await expect(page.getByRole('heading', { name: /sign up/i })).toBeVisible();
    // Check all inputs are there
    await expect(page.locator('input[name="username"]')).toBeVisible();
    await expect(page.locator('input[name="email"]')).toBeVisible();
    await expect(page.locator('input[name="password"]')).toBeVisible();
    await expect(page.locator('input[name="password2"]')).toBeVisible();
    // Check submit button shows up
    await expect(page.locator('input[type="submit"][value="Sign Up"]')).toBeVisible();
  });

  test('shows error when passwords do not match', async ({ page }) => {
    await page.fill('input[name="username"]', 'newuser');
    await page.fill('input[name="email"]', 'new@user.com');
    await page.fill('input[name="password"]', 'password1');
    await page.fill('input[name="password2"]', 'password2');
    await page.click('input[type="submit"]');
    // Should show password mismatch error
    const errorLocator = page.locator('.error');
    await expect(errorLocator).toBeVisible();
    await expect(errorLocator).toContainText('The two passwords do not match');
  });

  test('allows successful registration', async ({ page }) => {
    const unique = Date.now();
    await page.fill('input[name="username"]', `user${unique}`);
    await page.fill('input[name="email"]', `user${unique}@example.com`);
    await page.fill('input[name="password"]', 'safepass');
    await page.fill('input[name="password2"]', 'safepass');
    await page.click('input[type="submit"]');
    // Should redirect to home with success message
    await expect(page).toHaveURL('/');
    await expect(page.getByText('You were successfully registered and are now logged in.')).toBeVisible();
  });
});
