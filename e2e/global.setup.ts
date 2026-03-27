import { test as setup, expect } from "@playwright/test";
import { urls } from "./playwright.config";

const AUTH_FILE = "playwright/.auth/user.json";

setup("authenticate via Platform SSO", async ({ page }) => {
  // Navigate to Platform login
  await page.goto(`${urls.platform}/login`);

  // Fill credentials
  await page.getByLabel("Email").fill(process.env.TEST_EMAIL || "jolmos@runmyprocess.com");
  await page.getByLabel("Password").fill(process.env.TEST_PASSWORD || "");

  // Submit login form
  await page.getByRole("button", { name: /sign in|log in/i }).click();

  // Wait for dashboard redirect
  await page.waitForURL("**/dashboard/**", { timeout: 30_000 });
  await expect(page.getByRole("heading")).toBeVisible();

  // Save auth state
  await page.context().storageState({ path: AUTH_FILE });
});
