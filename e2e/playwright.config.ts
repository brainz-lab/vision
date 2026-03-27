import { defineConfig, devices } from "@playwright/test";

const isCI = !!process.env.CI;

// Environment-based URLs
const ENV = {
  staging: {
    platform: "https://platform.staging.fluyenta.com",
    signal: "https://signal.staging.fluyenta.com",
    dendrite: "https://dendrite.staging.fluyenta.com",
    pulse: "https://pulse.staging.fluyenta.com",
    recall: "https://recall.staging.fluyenta.com",
    reflex: "https://reflex.staging.fluyenta.com",
    beacon: "https://beacon.staging.fluyenta.com",
    flux: "https://flux.staging.fluyenta.com",
    cortex: "https://cortex.staging.fluyenta.com",
    nexus: "https://nexus.staging.fluyenta.com",
    vault: "https://vault.staging.fluyenta.com",
    synapse: "https://synapse.staging.fluyenta.com",
    nerve: "https://nerve.staging.fluyenta.com",
    vision: "https://vision.staging.fluyenta.com",
    sentinel: "https://sentinel.staging.fluyenta.com",
    landing: "https://landing.staging.fluyenta.com",
  },
  local: {
    platform: "http://localhost:3000",
    signal: "http://localhost:4011",
    dendrite: "http://localhost:4016",
    pulse: "http://localhost:4003",
    recall: "http://localhost:4001",
    reflex: "http://localhost:4002",
    beacon: "http://localhost:4012",
    flux: "http://localhost:4004",
    cortex: "http://localhost:4015",
    nexus: "http://localhost:4022",
    vault: "http://localhost:4006",
    synapse: "http://localhost:4021",
    nerve: "http://localhost:4017",
    vision: "http://localhost:4013",
    sentinel: "http://localhost:4014",
    landing: "http://localhost:4000",
  },
};

const env = (process.env.TEST_ENV as "staging" | "local") || "staging";

export const urls = ENV[env];

export default defineConfig({
  testDir: "./tests",
  fullyParallel: false,
  forbidOnly: isCI,
  retries: isCI ? 2 : 0,
  workers: 1,
  reporter: isCI
    ? [["github"], ["html", { open: "never" }]]
    : [["html", { open: "on-failure" }]],
  timeout: 60_000,
  expect: { timeout: 10_000 },

  use: {
    baseURL: urls.platform,
    trace: "on-first-retry",
    screenshot: "only-on-failure",
    video: "on-first-retry",
    actionTimeout: 15_000,
    navigationTimeout: 30_000,
  },

  projects: [
    {
      name: "setup",
      testMatch: /global\.setup\.ts/,
    },
    {
      name: "chromium",
      use: {
        ...devices["Desktop Chrome"],
        storageState: "playwright/.auth/user.json",
      },
      dependencies: ["setup"],
    },
  ],
});
