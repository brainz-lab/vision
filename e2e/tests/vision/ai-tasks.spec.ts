import { test, expect } from "@playwright/test";
import { urls } from "../../playwright.config";
import {
  assertPageHeading,
  assertEmptyState,
} from "../../helpers/assertions";
import { clickSidebarLink } from "../../helpers/navigation";
import { selectTestProject } from "../../helpers/project";

test.describe("Vision - AI Tasks", { tag: "@feature" }, () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(`${urls.vision}/dashboard`);
    await page.waitForLoadState("networkidle");
    await selectTestProject(page);
    await clickSidebarLink(page, "AI Tasks");
  });

  test("displays page heading", async ({ page }) => {
    await assertPageHeading(
      page,
      "AI Tasks",
      "Autonomous browser automation tasks",
    );
  });

  test("shows empty state when no tasks exist", async ({ page }) => {
    await assertEmptyState(page, /no ai tasks yet/i);
  });

  test("empty state explains tasks are created via MCP or API", async ({ page }) => {
    await expect(
      page.getByText(/tasks are created via mcp tools or the api/i),
    ).toBeVisible();
  });

  test("table headers are correct when tasks exist", async ({ page }) => {
    const table = page.locator("table");
    const isTableVisible = await table.isVisible().catch(() => false);
    if (isTableVisible) {
      await expect(table.getByRole("columnheader", { name: "Task" })).toBeVisible();
      await expect(table.getByRole("columnheader", { name: "Status" })).toBeVisible();
      await expect(table.getByRole("columnheader", { name: "Model" })).toBeVisible();
      await expect(table.getByRole("columnheader", { name: "Steps" })).toBeVisible();
      await expect(table.getByRole("columnheader", { name: "Tokens" })).toBeVisible();
      await expect(table.getByRole("columnheader", { name: "Duration" })).toBeVisible();
      await expect(table.getByRole("columnheader", { name: "Created" })).toBeVisible();
    }
  });
});
