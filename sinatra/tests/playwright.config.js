// @ts-check
const { defineConfig, devices } = require('@playwright/test');

module.exports = defineConfig({
  testDir: './e2e',           
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: 'html',
  use: {
    baseURL: 'http://127.0.0.1:4568',  
    trace: 'on-first-retry',
  }, 

  webServer: {
    command: 'bundle exec rackup -p 4568',
    url: 'http://127.0.0.1:4568',
    cwd: '../',
    reuseExistingServer: !process.env.CI,
  },

   /* Configure projects for major browsers */
   projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },

    {
      name: 'firefox',
      use: { ...devices['Desktop Firefox'] },
    },

    {
      name: 'webkit',
      use: { ...devices['Desktop Safari'] },
    },]
});
