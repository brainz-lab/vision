import { test, expect } from "@playwright/test";
import { urls } from "../../playwright.config";
import {
  assertPageHeading,
  assertEmptyState,
} from "../../helpers/assertions";
import { clickSidebarLink } from "../../helpers/navigation";
import { selectTestProject } from "../../helpers/project";

test.describe("Vision - Baselines", { tag: "@feature" }, () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(`${urls.vision}/dashboard`);
    await page.waitForLoadState("networkidle");
    await selectTestProject(page);
    await clickSidebarLink(page, "Baselines");
  });

  test("displays page heading", async ({ page }) => {
    await assertPageHeading(
      page,
      "Baselines",
      "Approved baseline screenshots for visual comparisons",
    );
  });

  test("shows empty state when no baselines exist", async ({ page }) => {
    await assertEmptyState(page, /no baselines yet/i);
  });

  test("empty state explains baselines are created from approved comparisons", async ({ page }) => {
    await expect(
      page.getByText(/baselines are created when you approve comparisons/i),
    ).toBeVisible();
  });
});
