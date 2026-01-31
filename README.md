# Vision

Visual regression testing and browser automation platform.

[![CI](https://github.com/brainz-lab/vision/actions/workflows/ci.yml/badge.svg)](https://github.com/brainz-lab/vision/actions/workflows/ci.yml)
[![CodeQL](https://github.com/brainz-lab/vision/actions/workflows/codeql.yml/badge.svg)](https://github.com/brainz-lab/vision/actions/workflows/codeql.yml)
[![codecov](https://codecov.io/gh/brainz-lab/vision/graph/badge.svg)](https://codecov.io/gh/brainz-lab/vision)
[![License: OSAaSy](https://img.shields.io/badge/License-OSAaSy-blue.svg)](LICENSE)
[![Ruby](https://img.shields.io/badge/Ruby-3.2+-red.svg)](https://www.ruby-lang.org)

## Quick Start

```bash
# Capture a screenshot
vision_capture(url: "https://example.com", viewport: "desktop")

# Run AI browser task
vision_task(instruction: "Add item to cart", start_url: "https://shop.example.com")
```

## Installation

### With Docker

```bash
docker pull brainzllc/vision:latest

docker run -d \
  -p 3000:3000 \
  -e DATABASE_URL=postgres://user:pass@host:5432/vision \
  -e REDIS_URL=redis://host:6379/11 \
  -e RAILS_MASTER_KEY=your-master-key \
  brainzllc/vision:latest
```

### Local Development

```bash
bin/setup
bin/rails server
```

## Configuration

| Variable | Description | Required |
|----------|-------------|----------|
| `DATABASE_URL` | PostgreSQL connection | Yes |
| `REDIS_URL` | Redis for ActionCable/jobs | Yes |
| `RAILS_MASTER_KEY` | Rails credentials | Yes |
| `AWS_ENDPOINT` | S3/MinIO endpoint | Yes |
| `AWS_ACCESS_KEY_ID` | S3 access key | Yes |
| `AWS_SECRET_ACCESS_KEY` | S3 secret key | Yes |
| `AWS_BUCKET` | Bucket for screenshots | Yes |
| `BRAINZLAB_VAULT_URL` | Vault service URL | No |

### Tech Stack

- **Ruby** 3.4.7 / **Rails** 8.1
- **PostgreSQL** 16 (UUID primary keys)
- **Browser Engine**: Playwright (playwright-ruby-client)
- **Image Processing**: ImageMagick (mini_magick)
- **Storage**: ActiveStorage with S3/MinIO
- **Hotwire** (Turbo + Stimulus) / **Tailwind CSS**

## Usage

### Screenshot Capture

```ruby
POST /api/v1/snapshots
{
  "url": "https://example.com",
  "viewport": "desktop",
  "browser": "chromium",
  "hide_elements": [".cookie-banner", ".ads"]
}
```

### Visual Regression Testing

```ruby
# Create baseline
POST /api/v1/pages
{ "url": "https://example.com/pricing", "name": "Pricing Page" }

# Capture and compare
POST /api/v1/test_runs
{ "page_ids": ["page_uuid1", "page_uuid2"] }

# Review results
GET /api/v1/test_runs/:id
```

### AI Browser Automation

```ruby
# Autonomous task execution
vision_task(
  instruction: "Add item 12345 to cart and proceed to checkout",
  start_url: "https://shop.example.com",
  credential: "shop-login"  # Auto-login from Vault
)
```

### Browser Support

| Browser | Viewports |
|---------|-----------|
| Chromium | Desktop (1280x720), Mobile (375x812), Tablet (768x1024) |
| Firefox | Desktop |
| WebKit | Desktop, Mobile |

### Credential Integration

Vision integrates with Vault for secure credential storage:

```ruby
# Store credential in Vault
vision_credential(action: "store", name: "github", username: "user", password: "secret")

# Use in automation
vision_task(
  instruction: "Create new issue",
  start_url: "https://github.com/org/repo/issues/new",
  credential: "github"
)
```

## API Reference

### Snapshots
- `GET /api/v1/snapshots` - List snapshots
- `POST /api/v1/snapshots` - Capture screenshot
- `POST /api/v1/snapshots/:id/compare` - Compare to baseline

### Test Runs
- `GET /api/v1/test_runs` - List test runs
- `POST /api/v1/test_runs` - Start test run
- `GET /api/v1/test_runs/:id` - Get run with comparisons

### Comparisons
- `POST /api/v1/comparisons/:id/approve` - Approve changes
- `POST /api/v1/comparisons/:id/reject` - Reject changes

### MCP Tools

| Tool | Description |
|------|-------------|
| `vision_capture` | Take screenshot of a URL |
| `vision_compare` | Compare current state to baseline |
| `vision_test` | Run full visual test suite |
| `vision_approve` | Approve changes, update baseline |
| `vision_task` | Execute autonomous AI browser task |
| `vision_ai_action` | Single AI-powered browser action |
| `vision_perform` | Direct browser action without AI |
| `vision_extract` | Extract structured data from page |

Full documentation: [docs.brainzlab.ai/products/vision](https://docs.brainzlab.ai/products/vision/overview)

## Self-Hosting

### Docker Compose

```yaml
services:
  vision:
    image: brainzllc/vision:latest
    ports:
      - "4008:3000"
    environment:
      DATABASE_URL: postgres://user:pass@db:5432/vision
      REDIS_URL: redis://redis:6379/11
      RAILS_MASTER_KEY: ${RAILS_MASTER_KEY}
      AWS_ENDPOINT: http://minio:9000
      AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID}
      AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY}
      AWS_BUCKET: vision-screenshots
    depends_on:
      - db
      - redis
      - minio
```

### Testing

```bash
bin/rails test
bin/rubocop
```

## Contributing

See [CONTRIBUTING.md](../CONTRIBUTING.md) for development setup and contribution guidelines.

## License

This project is licensed under the [OSAaSy License](LICENSE).
