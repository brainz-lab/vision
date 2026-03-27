import { test, expect } from "@playwright/test";
import { urls } from "../../playwright.config";
import {
  assertPageHeading,
  assertEmptyState,
} from "../../helpers/assertions";
import { clickSidebarLink } from "../../helpers/navigation";
import { selectTestProject } from "../../helpers/project";

test.describe("Vision - Test Runs", { tag: "@feature" }, () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(`${urls.vision}/dashboard`);
    await page.waitForLoadState("networkidle");
    await selectTestProject(page);
    await clickSidebarLink(page, "Test Runs");
  });

  test("displays page heading", async ({ page }) => {
    await assertPageHeading(
      page,
      "Test Runs",
      "Visual regression test history",
    );
  });

  test("shows empty state when no test runs exist", async ({ page }) => {
    await assertEmptyState(page, /no test runs yet/i);
  });

  test("empty state explains test runs are triggered via API or MCP", async ({ page }) => {
    await expect(
      page.getByText(/test runs are triggered via the api or mcp tools/i),
    ).toBeVisible();
  });

  test("table headers are correct when runs exist", async ({ page }) => {
    const table = page.locator("table");
    const isTableVisible = await table.isVisible().catch(() => false);
    if (isTableVisible) {
      await expect(table.getByRole("columnheader", { name: "Run" })).toBeVisible();
      await expect(table.getByRole("columnheader", { name: "Status" })).toBeVisible();
      await expect(table.getByRole("columnheader", { name: "Comparisons" })).toBeVisible();
      await expect(table.getByRole("columnheader", { name: "Passed" })).toBeVisible();
      await expect(table.getByRole("columnheader", { name: "Failed" })).toBeVisible();
      await expect(table.getByRole("columnheader", { name: "Created" })).toBeVisible();
    }
  });
});
