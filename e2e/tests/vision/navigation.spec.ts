import { test, expect } from "@playwright/test";
import { urls } from "../../playwright.config";
import { clickSidebarLink, assertSidebarLinks } from "../../helpers/navigation";
import { TEST_PROJECT_NAME } from "../../helpers/config";
import { selectTestProject } from "../../helpers/project";

const VISION_SIDEBAR_LINKS = [
  "Pages",
  "Test Runs",
  "Baselines",
  "AI Tasks",
  "MCP Setup",
  "Settings",
];

test.describe("Vision - Navigation", { tag: "@smoke" }, () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(`${urls.vision}/dashboard`);
    await page.waitForLoadState("networkidle");
    await selectTestProject(page);
  });

  test("sidebar displays all navigation links", async ({ page }) => {
    await assertSidebarLinks(page, VISION_SIDEBAR_LINKS);
  });

  test("sidebar shows Fluyenta Vision branding", async ({ page }) => {
    await expect(page.getByText("Vision")).toBeVisible();
  });

  test("sidebar shows project name (My App)", async ({ page }) => {
    await expect(
      page.getByRole("link", { name: new RegExp(TEST_PROJECT_NAME, "i") }),
    ).toBeVisible();
  });

  test("'All Products' link points to Platform", async ({ page }) => {
    const link = page.getByRole("link", { name: "All Products" });
    await expect(link).toBeVisible();
    await expect(link).toHaveAttribute(
      "href",
      expect.stringContaining("platform"),
    );
  });

  test("sidebar shows AI Assistant link", async ({ page }) => {
    await expect(
      page.getByRole("navigation").getByRole("link", { name: "AI Assistant" }),
    ).toBeVisible();
  });

  for (const linkName of VISION_SIDEBAR_LINKS) {
    test(`navigates to ${linkName} page`, async ({ page }) => {
      await clickSidebarLink(page, linkName);
      await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
    });
  }
});
