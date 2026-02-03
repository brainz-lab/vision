# CLAUDE.md

> **Secrets Reference**: See `../.secrets.md` (gitignored) for master keys, server access, and MCP tokens.

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project: Vision by Brainz Lab

Visual regression testing and browser automation platform for UI validation.

**Domain**: vision.brainzlab.ai

**Tagline**: "See what your users see"

**Status**: Implemented - Rails 8 application with Playwright browser automation

## Architecture

```
+---------------------------------------------------------------------+
|                          VISION (Rails 8)                            |
|                                                                      |
|  +---------------+  +---------------+  +---------------+             |
|  |   Dashboard   |  |      API      |  |  MCP Server   |             |
|  |   (Hotwire)   |  |  (JSON API)   |  |    (Ruby)     |             |
|  | /dashboard/*  |  |  /api/v1/*    |  |    /mcp/*     |             |
|  +---------------+  +---------------+  +---------------+             |
|                            |                   |                     |
|                            v                   v                     |
|              +------------------------------------------+            |
|              |   PostgreSQL + S3/Minio + Playwright     |            |
|              +------------------------------------------+            |
+---------------------------------------------------------------------+
        ^
        | Trigger
+-------+-------+
| CI/CD/Synapse |
| GitHub/GitLab |
+---------------+
```

## Tech Stack

- **Backend**: Rails 8 API + Dashboard
- **Frontend**: Hotwire (Turbo + Stimulus), Tailwind CSS
- **Database**: PostgreSQL (with UUID primary keys)
- **Browser Engine**: Playwright (via playwright-ruby-client)
- **Image Processing**: ImageMagick (via mini_magick)
- **Storage**: ActiveStorage with S3/Minio
- **Background Jobs**: Solid Queue
- **Real-time**: ActionCable (live results)

## Common Commands

```bash
# Development
bin/rails server
bin/rails console
bin/rails db:migrate

# Testing
bin/rails test
bin/rails test test/models/snapshot_test.rb

# Docker (from brainzlab root)
docker-compose --profile vision up
docker-compose exec vision bin/rails db:migrate

# Database
bin/rails db:create db:migrate
bin/rails db:seed

# Tailwind
bin/rails tailwindcss:build
```

## Key Models

| Model | Purpose |
|-------|---------|
| **Project** | Test project config, links to Platform via `platform_project_id` |
| **Page** | URL/path to capture with settings |
| **BrowserConfig** | Browser/viewport configuration (chromium, firefox, webkit) |
| **Baseline** | Approved baseline screenshot |
| **Snapshot** | Captured screenshot |
| **Comparison** | Diff result between baseline and snapshot |
| **TestRun** | Collection of comparisons for a deployment |
| **TestCase** | E2E test definition with steps |
| **Credential** | Reference to credentials stored in Vault (never stores actual secrets) |

## Screenshot Capture Flow

1. **Create Snapshot** - API/MCP creates pending snapshot record
2. **CaptureScreenshotJob** - Background job runs Playwright capture
3. **ScreenshotService** - Navigates, waits, hides elements, captures
4. **Upload to S3** - Screenshots stored via ActiveStorage
5. **CompareScreenshotsJob** - Compares to baseline if exists
6. **ComparisonService** - Runs ImageMagick diff, stores result

## Key Services

| Service | Responsibility |
|---------|----------------|
| `ScreenshotService` | Playwright capture with element hiding/masking |
| `ComparisonService` | Orchestrates baseline vs snapshot comparison |
| `DiffService` | ImageMagick pixel-level image diffing |
| `BrowserPool` | Connection pool for Playwright instances |
| `TestRunner` | Executes full test suites |
| `PlatformClient` | Platform API key validation |
| `VaultClient` | Secure credential fetching from Vault service |
| `Ai::CredentialInjector` | Injects credentials into browser automation flows |

## MCP Tools

| Tool | Description |
|------|-------------|
| `vision_capture` | Take screenshot of a URL |
| `vision_compare` | Compare current state to baseline |
| `vision_test` | Run full visual test suite |
| `vision_approve` | Approve changes, update baseline |
| `vision_list_failures` | List failed comparisons needing review |
| `vision_task` | Execute autonomous AI browser task (supports credentials) |
| `vision_ai_action` | Single AI-powered browser action |
| `vision_perform` | Direct browser action without AI |
| `vision_extract` | Extract structured data from page |
| `vision_credential` | Store/manage credentials in Vault |

## API Endpoints

**Projects**:
- `POST /api/v1/projects/provision` - Auto-provision project (master key)
- `GET /api/v1/projects/lookup` - Find project by platform_project_id

**Pages**:
- `GET /api/v1/pages` - List pages
- `POST /api/v1/pages` - Create page
- `GET /api/v1/pages/:id` - Get page with baselines

**Snapshots**:
- `GET /api/v1/snapshots` - List snapshots
- `POST /api/v1/snapshots` - Capture screenshot
- `POST /api/v1/snapshots/:id/compare` - Compare to baseline

**Test Runs**:
- `GET /api/v1/test_runs` - List test runs
- `POST /api/v1/test_runs` - Start test run
- `GET /api/v1/test_runs/:id` - Get run with comparisons

**Comparisons**:
- `POST /api/v1/comparisons/:id/approve` - Approve changes
- `POST /api/v1/comparisons/:id/reject` - Reject changes
- `POST /api/v1/comparisons/:id/update_baseline` - Set as new baseline

**MCP**:
- `GET /mcp/tools` - List tools
- `POST /mcp/tools/:name` - Call tool
- `POST /mcp/rpc` - JSON-RPC protocol

Authentication: `Authorization: Bearer <key>` or `X-API-Key: <key>`

## Browser Support

| Browser | Viewports |
|---------|-----------|
| Chromium | Desktop (1280x720), Mobile (375x812), Tablet (768x1024) |
| Firefox | Desktop |
| WebKit | Desktop, Mobile |

## Threshold Configuration

- Default threshold: 1% (0.01)
- Comparisons with diff_percentage <= threshold pass
- Failed comparisons require manual review

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `DATABASE_URL` | PostgreSQL connection |
| `REDIS_URL` | Redis for ActionCable/jobs |
| `VISION_MASTER_KEY` | Master key for provisioning |
| `AWS_ENDPOINT` | S3/MinIO endpoint |
| `AWS_ACCESS_KEY_ID` | S3 access key |
| `AWS_SECRET_ACCESS_KEY` | S3 secret key |
| `AWS_BUCKET` | Bucket for screenshots |
| `BRAINZLAB_PLATFORM_URL` | Platform service URL |
| `BRAINZLAB_VAULT_URL` | Vault service URL for credentials |
| `VAULT_ACCESS_TOKEN` | Default Vault access token |

## Vault Integration (Credential Management)

Vision integrates with the Vault service for secure credential storage. Credentials are **never stored in Vision** - only references to Vault paths.

### Storing Credentials

```ruby
# Via MCP tool
vision_credential(action: "store", name: "github", username: "user", password: "secret")

# Via API
POST /api/v1/credentials
{ "name": "github", "username": "user", "password": "secret", "service_url": "https://github.com/*" }

# Via model
credential = project.credentials.create!(name: "github", service_url: "https://github.com/*")
credential.store!(username: "user", password: "secret")
```

### Using Credentials in Browser Automation

```ruby
# MCP tool with automatic login
vision_task(
  instruction: "Add item 12345 to my collection",
  start_url: "https://example.com",
  credential: "my-service"  # Will auto-login before task
)

# Programmatic usage
credential = project.find_credential("my-service")
injector = Ai::CredentialInjector.new(browser: browser, session_id: sid, project: project)
injector.login(credential)
```

### Security Model

- Credentials encrypted with AES-256-GCM in Vault
- Vision stores only Vault path references
- Audit logging for all credential access
- Environment separation (production/staging/development)
- Automatic credential rotation support

## Docker

```bash
# Start Vision
docker-compose --profile vision up

# Run migrations
docker-compose exec vision bin/rails db:migrate

# Rails console
docker-compose exec vision bin/rails console

# Access at http://localhost:4008
```

## Kamal Production Access

**IMPORTANT**: When using `kamal app exec --reuse`, docker exec doesn't inherit container environment variables. You must pass `SECRET_KEY_BASE` explicitly.

```bash
# Navigate to this service directory
cd /Users/afmp/brainz/brainzlab/vision

# Get the master key (used as SECRET_KEY_BASE)
cat config/master.key

# Run Rails console commands
kamal app exec -p --reuse -e SECRET_KEY_BASE:<master_key> 'bin/rails runner "<ruby_code>"'

# Example: Count snapshots
kamal app exec -p --reuse -e SECRET_KEY_BASE:<master_key> 'bin/rails runner "puts Snapshot.count"'
```

### Running Complex Scripts

For multi-line Ruby scripts, create a local file, scp to server, docker cp into container, then run with rails runner. See main brainzlab/CLAUDE.md for details.

### Other Kamal Commands

```bash
kamal deploy              # Deploy
kamal app logs -f         # View logs
kamal lock release        # Release stuck lock
kamal secrets print       # Print evaluated secrets
```
