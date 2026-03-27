import { test, expect } from "@playwright/test";
import { urls } from "../../playwright.config";
import {
  assertPageHeading,
  assertCreateButton,
  assertEmptyState,
} from "../../helpers/assertions";
import { clickSidebarLink } from "../../helpers/navigation";
import { selectTestProject } from "../../helpers/project";

test.describe("Vision - Pages", { tag: "@feature" }, () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(`${urls.vision}/dashboard`);
    await page.waitForLoadState("networkidle");
    await selectTestProject(page);
    await clickSidebarLink(page, "Pages");
  });

  test("displays page heading", async ({ page }) => {
    await assertPageHeading(page, "Pages");
  });

  test("shows New Page button", async ({ page }) => {
    await assertCreateButton(page, /new page/i);
  });

  test("shows empty state when no pages configured", async ({ page }) => {
    await assertEmptyState(page, /no pages configured/i);
  });

  test("empty state shows 'Add your first page' link", async ({ page }) => {
    await expect(
      page.getByRole("link", { name: /add your first page/i }),
    ).toBeVisible();
  });

  test("New Page button navigates to new page form", async ({ page }) => {
    await page.getByRole("link", { name: /new page/i }).click();
    await page.waitForLoadState("networkidle");
    await expect(page.getByRole("heading", { level: 1, name: /add new page/i })).toBeVisible();
  });

  test("new page form shows Name field", async ({ page }) => {
    await page.getByRole("link", { name: /new page/i }).click();
    await page.waitForLoadState("networkidle");
    await expect(page.getByLabel("Name")).toBeVisible();
  });

  test("new page form shows Path field", async ({ page }) => {
    await page.getByRole("link", { name: /new page/i }).click();
    await page.waitForLoadState("networkidle");
    await expect(page.getByLabel("Path")).toBeVisible();
  });

  test("new page form shows capture settings section", async ({ page }) => {
    await page.getByRole("link", { name: /new page/i }).click();
    await page.waitForLoadState("networkidle");
    await expect(page.getByText("Capture Settings")).toBeVisible();
  });

  test("new page form shows Wait for Selector field", async ({ page }) => {
    await page.getByRole("link", { name: /new page/i }).click();
    await page.waitForLoadState("networkidle");
    await expect(page.getByLabel("Wait for Selector")).toBeVisible();
  });

  test("new page form shows Additional Wait field", async ({ page }) => {
    await page.getByRole("link", { name: /new page/i }).click();
    await page.waitForLoadState("networkidle");
    await expect(page.getByLabel("Additional Wait")).toBeVisible();
  });

  test("new page form shows Create Page submit button", async ({ page }) => {
    await page.getByRole("link", { name: /new page/i }).click();
    await page.waitForLoadState("networkidle");
    await expect(
      page.getByRole("button", { name: "Create Page" }),
    ).toBeVisible();
  });

  test("new page form shows Cancel link", async ({ page }) => {
    await page.getByRole("link", { name: /new page/i }).click();
    await page.waitForLoadState("networkidle");
    await expect(
      page.getByRole("link", { name: "Cancel" }),
    ).toBeVisible();
  });

  test("new page form shows Back to Pages breadcrumb", async ({ page }) => {
    await page.getByRole("link", { name: /new page/i }).click();
    await page.waitForLoadState("networkidle");
    await expect(
      page.getByRole("link", { name: /back to pages/i }),
    ).toBeVisible();
  });
});
