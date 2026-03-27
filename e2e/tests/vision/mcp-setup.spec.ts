import { test, expect } from "@playwright/test";
import { urls } from "../../playwright.config";
import { assertPageHeading } from "../../helpers/assertions";
import { clickSidebarLink } from "../../helpers/navigation";
import { selectTestProject } from "../../helpers/project";

test.describe("Vision - MCP Setup", { tag: "@feature" }, () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(`${urls.vision}/dashboard`);
    await page.waitForLoadState("networkidle");
    await selectTestProject(page);
    await clickSidebarLink(page, "MCP Setup");
  });

  test("displays page heading", async ({ page }) => {
    await assertPageHeading(
      page,
      "MCP Setup Guide",
      "Connect Claude or other AI assistants to Vision using the Model Context Protocol",
    );
  });

  test("Step 1: shows Get your API key section", async ({ page }) => {
    await expect(
      page.getByRole("heading", { name: "Get your API key" }),
    ).toBeVisible();
  });

  test("Step 1: shows API key value", async ({ page }) => {
    await expect(
      page.locator("code").filter({ hasText: /^vis_api_/ }),
    ).toBeVisible();
  });

  test("Step 1: shows Copy button", async ({ page }) => {
    await expect(
      page.getByRole("button", { name: "Copy" }).first(),
    ).toBeVisible();
  });

  test("Step 1: shows Regenerate API Key button", async ({ page }) => {
    await expect(
      page.getByRole("button", { name: /regenerate api key/i }),
    ).toBeVisible();
  });

  test("Step 2: shows Configure Claude Code section", async ({ page }) => {
    await expect(
      page.getByRole("heading", { name: "Configure Claude Code" }),
    ).toBeVisible();
  });

  test("Step 2: shows MCP server configuration JSON", async ({ page }) => {
    await expect(page.getByText("mcpServers")).toBeVisible();
    await expect(page.getByText("/mcp/rpc")).toBeVisible();
  });

  test("Step 3: shows usage instructions", async ({ page }) => {
    await expect(
      page.getByRole("heading", { name: "Start using Vision with Claude" }),
    ).toBeVisible();
  });

  test("Step 3: shows example prompts", async ({ page }) => {
    await expect(
      page.getByText("Capture a screenshot of the homepage"),
    ).toBeVisible();
    await expect(
      page.getByText("Run a visual regression test on all pages"),
    ).toBeVisible();
  });

  test("shows Available MCP tools section", async ({ page }) => {
    await expect(
      page.getByRole("heading", { name: "Available MCP tools" }),
    ).toBeVisible();
  });

  test("lists vision_capture tool", async ({ page }) => {
    await expect(page.getByText("vision_capture")).toBeVisible();
  });

  test("lists vision_compare tool", async ({ page }) => {
    await expect(page.getByText("vision_compare")).toBeVisible();
  });

  test("lists vision_test tool", async ({ page }) => {
    await expect(page.getByText("vision_test")).toBeVisible();
  });

  test("lists vision_task tool", async ({ page }) => {
    await expect(page.getByText("vision_task")).toBeVisible();
  });

  test("shows Example workflows section", async ({ page }) => {
    await expect(
      page.getByRole("heading", { name: "Example workflows" }),
    ).toBeVisible();
  });

  test("shows Test MCP connection section with curl example", async ({ page }) => {
    await expect(
      page.getByRole("heading", { name: "Test MCP connection" }),
    ).toBeVisible();
    await expect(page.getByText("curl")).toBeVisible();
  });
});
