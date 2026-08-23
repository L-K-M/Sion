import { defineConfig } from '@playwright/test';

/**
 * Two tiers (PLAN.md §15.2):
 *  - `web`: the renderer served by vite preview in plain Chromium with the
 *    browser platform fallback — the fast, primary suite.
 *  - `electron`: the Electron smoke suite (_electron.launch).
 */
export default defineConfig({
  testDir: 'tests/e2e',
  timeout: 60_000,
  expect: { timeout: 15_000 },
  fullyParallel: false,
  workers: 1,
  retries: process.env.CI ? 1 : 0,
  forbidOnly: !!process.env.CI,
  reporter: process.env.CI ? [['github'], ['html', { open: 'never' }]] : 'list',
  use: {
    trace: 'retain-on-failure',
  },
  webServer: process.env.THALYX_SKIP_WEB
    ? undefined
    : {
        command: 'npx vite preview --config vite.preview.config.ts --port 4173 --strictPort',
        url: 'http://localhost:4173',
        reuseExistingServer: !process.env.CI,
        timeout: 60_000,
      },
  projects: [
    {
      name: 'web',
      testMatch: /web\/.*\.spec\.ts/,
      use: { baseURL: 'http://localhost:4173' },
    },
    {
      name: 'electron',
      testMatch: /electron\/.*\.spec\.ts/,
    },
  ],
});
