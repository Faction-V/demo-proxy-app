# gofapi -> platform-api Migration Status

## Overview

This document tracks the migration of endpoints from the Clojure gofapi service to the Python platform-api service as part of the foreign user authentication implementation (BE-955).

Three repos are involved:

| Repo | Role |
|------|------|
| **platform-api** (`src/routes/users_auth.py`) | Public-facing endpoints with foreign user auth |
| **clj-pg-wrapper** | PostgreSQL access layer (users, stories, projects, sources, storyplan configs) |
| **demo-proxy-app** (`app/main.py`) | Middleware proxy that injects auth headers and source IDs |

---

## Completed Migrations -- platform-api endpoints

### User Authentication & Session

| Method | Path | Description | Notes |
|--------|------|-------------|-------|
| POST | `/signup` | User signup | Standard email/password |
| POST | `/login` | User login | Returns JWT |
| POST | `/user/otp/sign-in` | OTP sign-in | Sends OTP code |
| POST | `/user/otp/validate` | OTP validate | Validates OTP code |
| GET | `/user/current-user` | Current user info | Foreign user auth + session |
| GET | `/user/current-token` | JWT token | 30-day expiration, includes `org_id` |
| POST | `/user/sign-out` | Sign out | Invalidates session |
| GET | `/user/membership/current-membership` | Subscription plan | Returns basic/premium |

### Organization & Prompts

| Method | Path | Description | Notes |
|--------|------|-------------|-------|
| GET | `/prompts` | Org prompts | Extracts org_id from API key |
| GET | `/organizations/me` | User's organizations | Supports JWT + foreign auth (`src/routes/organizations.py`) |

### Storyplan Configuration (full CRUD)

| Method | Path | Description | Notes |
|--------|------|-------------|-------|
| GET | `/user/storyplan-config` | List configs | Via clj-pg-wrapper |
| POST | `/user/storyplan-config` | Create config | |
| PUT | `/user/storyplan-config` | Update config | |
| DELETE | `/user/storyplan-config` | Delete config | |
| GET | `/user/storyplan-config/default` | Get default config | |
| POST | `/user/storyplan-config/default` | Set default config | |

### Guardrails

| Method | Path | Description | Notes |
|--------|------|-------------|-------|
| POST | `/configs/guardrails/check/prompt` | Check prompt | Extracts org_id from API key |

### Projects

| Method | Path | Description | Notes |
|--------|------|-------------|-------|
| GET | `/project/list` | List projects | Enriched with sources, counts, hero images |

### Events

| Method | Path | Description | Notes |
|--------|------|-------------|-------|
| GET | `/events` | Story events | Proxies to capitol-llm; transforms `socket_address` -> `socketAddress` |
| PATCH | `/events/bulk` | Bulk update events | Forwards to capitol-llm `/bulk_update/{story_id}` |

### Stories

| Method | Path | Description | Notes |
|--------|------|-------------|-------|
| GET | `/stories/mini` | Story preview | Returns `{"createdAt": null}` for new stories (triggers generation) |
| POST | `/chat/async` | Story generation | Returns WebSocket address; auto-injects source IDs (via demo-proxy-app) |
| POST | `/chat` | Synchronous chat | Direct chat endpoint |
| POST | `/chat/suggestions/block` | AI block editing | Suggestions for specific story block |
| POST | `/chat/suggestions/draft` | AI draft suggestions | Draft-level suggestions |
| GET | `/stories/story-plan-config` | Story plan config | Via clj-pg-wrapper |
| GET | `/stories/story` | Get story details | Via clj-pg-wrapper |
| PUT | `/stories/story` | Update story | Via clj-pg-wrapper |

### Source Upload (synchronous)

| Method | Path | Description | Notes |
|--------|------|-------------|-------|
| POST | `/sources/upload-source/sync` | Upload JSON/URL source | Proxies to clj-pg-wrapper; optional embedding generation |
| POST | `/sources/upload-source/file` | Upload PDF/image file | Multipart; proxies to clj-pg-wrapper |

### Source Upload (async with WebSocket)

| Method | Path | Description | Notes |
|--------|------|-------------|-------|
| POST | `/sources/ws` | Create WebSocket address | Returns `ws-address` for status updates |
| WebSocket | `/ws/{ws_uuid}` | WebSocket handler | Subscribes to Redis pub/sub channel |
| POST | `/sources/upload-source` | Async upload | Returns immediately; publishes status to Redis |
| POST | `/user/sources/ws` | Alias with `/user` prefix | gofapi compatibility |
| WebSocket | `/user/ws/{ws_uuid}` | Alias with `/user` prefix | gofapi compatibility |
| POST | `/user/sources/upload-source` | Alias with `/user` prefix | gofapi compatibility |

### Feedback

| Method | Path | Description | Notes |
|--------|------|-------------|-------|
| GET | `/user/feedback/thumbs` | Check feedback | Check if user gave feedback for a story |
| POST | `/user/feedback/thumbs` | Submit feedback | Thumbs up/down with optional comment |

---

## Completed Migrations -- clj-pg-wrapper endpoints

These are the database-access endpoints called by platform-api (not exposed directly to the frontend):

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/v1/users/external` | Get-or-create foreign user |
| GET | `/api/v1/projects/list` | Enriched project listing |
| POST | `/story` | Create story record |
| GET | `/story/basic-info` | Get story basic info |
| GET | `/story` | Get full story details |
| PUT | `/story` | Update story record |
| GET | `/user/storyplan-config/*` | Storyplan config CRUD |
| POST | `/api/v1/sources/upload-source/sync` | Source upload (JSON/URL) |
| POST | `/api/v1/sources/upload-source/file` | Source upload (file) |

---

## Completed Migrations -- demo-proxy-app

| Feature | Description |
|---------|-------------|
| Header injection | `X-API-Key`, `X-User-ID`, `X-Domain` on every request |
| Path stripping | Removes `/v1/` prefix from React library paths |
| Source auto-injection | Queries PostgreSQL for 10 most recent embedded sources, injects `user_pre_processed_sources` with download URLs into `POST /chat/async` |
| `X-Forwarded-Host` | Enables correct WebSocket address generation in responses |

---

## Pending Migrations

### Tako Charts/Visualizations
**Priority: MEDIUM** - Data visualization features

- **GET /v2** - Get Tako chart preview link
  - Query params: `orgid=<uuid>&erid=<uuid>&l=...`
  - Used by: Chart/visualization rendering
  - Location: `gofapi/src/clj/gofapi/tako/routes.clj`

### Credits System
**Priority: LOW** - Usage tracking (may use DynamoDB directly)

- **GET /credits** - Get user credit balance
- **POST /credits/deduct** - Deduct credits for operations

### Sources (listing/deletion)
**Priority: LOW** - Source management

- **GET /sources** - List sources for organization
- **DELETE /sources/:id** - Remove source

### Story Versioning
**Priority: LOW** - Extended story functionality

- **GET /stories/:id/versions** - Get story versions
- **DELETE /stories/:id** - Delete story

---

## Architecture

### Authentication Flow

```
Customer Frontend  -->  Customer Backend  -->  demo-proxy-app  -->  platform-api
                        (injects X-User-ID)    (injects X-API-Key,   (validates key,
                                                X-Domain, sources)    get-or-create user)
                                                                        |
                                                                        v
                                                                   clj-pg-wrapper
                                                                   (PostgreSQL)
```

### Service Dependencies

| Service | Used For |
|---------|----------|
| capitol-llm | Story generation, events, suggestions |
| clj-pg-wrapper | PostgreSQL access (users, stories, projects, sources, configs) |
| Redis | Foreign user cache (5-min TTL), WebSocket pub/sub |
| DynamoDB | API key validation, storyplan configs |
| S3 | Source document storage |
| Lambda | Embedding generation |
| Qdrant | Vector search for story generation |

### Dual Authentication

All endpoints support both pathways:
1. **Foreign User Auth**: `X-API-Key` + `X-User-ID` headers (for customer integrations)
2. **Session Auth**: Cookie-based session (for internal/backward compatibility)

---

## Related Links

- **Epic:** [COM-21](https://capitolai.atlassian.net/browse/COM-21) - Deprecate clj-services
- **Task:** [COM-22](https://capitolai.atlassian.net/browse/COM-22) - Proxy Demo App POC
- **Demo:** [Loom Walkthrough](https://www.loom.com/share/88ac83881ab64fcfb05449a5086ac3f4)
- **Repos:** demo-proxy-app, platform-api, clj-pg-wrapper (all branch `BE-955-proxy-demo-app-poc`)
