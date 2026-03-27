import { test, expect } from "@playwright/test";
import { urls } from "../../playwright.config";
import { assertPageHeading } from "../../helpers/assertions";
import { clickSidebarLink } from "../../helpers/navigation";
import { selectTestProject } from "../../helpers/project";

test.describe("Vision - Settings", { tag: "@feature" }, () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(`${urls.vision}/dashboard`);
    await page.waitForLoadState("networkidle");
    await selectTestProject(page);
    await clickSidebarLink(page, "Settings");
  });

  test("displays page heading with project name", async ({ page }) => {
    await assertPageHeading(page, "Project Settings");
    await expect(page.getByText("My App")).toBeVisible();
  });

  test("shows Project Details section", async ({ page }) => {
    await expect(
      page.getByRole("heading", { name: "Project Details" }),
    ).toBeVisible();
  });

  test("Project Details: shows Name field", async ({ page }) => {
    await expect(page.getByText("Name")).toBeVisible();
    await expect(page.getByText("My App")).toBeVisible();
  });

  test("Project Details: shows Base URL field", async ({ page }) => {
    await expect(page.getByText("Base URL")).toBeVisible();
  });

  test("Project Details: shows Platform Project ID field", async ({ page }) => {
    await expect(page.getByText("Platform Project ID")).toBeVisible();
  });

  test("Project Details: shows Created date", async ({ page }) => {
    await expect(page.getByText("Created")).toBeVisible();
  });

  test("shows API Access section", async ({ page }) => {
    await expect(
      page.getByRole("heading", { name: "API Access" }),
    ).toBeVisible();
  });

  test("API Access: shows authentication instructions", async ({ page }) => {
    await expect(
      page.getByText(/authorization: bearer/i),
    ).toBeVisible();
  });

  test("shows Statistics section", async ({ page }) => {
    await expect(
      page.getByRole("heading", { name: "Statistics" }),
    ).toBeVisible();
  });

  test("Statistics: shows Pages count", async ({ page }) => {
    await expect(page.getByText("Pages").last()).toBeVisible();
  });

  test("Statistics: shows Test Runs count", async ({ page }) => {
    await expect(page.getByText("Test Runs").last()).toBeVisible();
  });

  test("Statistics: shows Baselines count", async ({ page }) => {
    await expect(page.getByText("Baselines").last()).toBeVisible();
  });
});
