# gofapi → platform-api Migration Status

## Overview

This document tracks the migration of endpoints from the Clojure gofapi service to the Python platform-api service as part of the foreign user authentication implementation (BE-955).

## Completed Migrations ✅

### User Authentication & Management
- ✅ **GET /user/current-user** - Get current user information (supports foreign user auth)
- ✅ **GET /user/membership/current-membership** - Get user subscription/membership (dual pathway support)
- ✅ **GET /user/current-token** - Get JWT authentication token (30-day expiration, foreign user auth)

### Organization Resources
- ✅ **GET /prompts** - Get organization prompts by API key (alias for /org-prompts/:orgid)
- ✅ **GET /user/storyplan-config** - Get user's storyplan configurations (format settings)
- ✅ **GET /organizations/me** - Get user's organizations (supports foreign user auth)

### Guardrails
- ✅ **POST /configs/guardrails/check/prompt** - Check prompt against organization guardrails

### Project Management
- ✅ **GET /project/list** - List user projects with sources, counts, and hero images (gofapi-compatible)

### Events System
- ✅ **GET /events** - Get events for a story (proxies to capitol-llm)

### Story Management
- ✅ **GET /stories/mini** - Get story mini view with database info + capitol-llm attributes
  - **Key Feature**: Returns 200 with `{"createdAt": null}` for new stories (instead of 404)
  - Frontend checks `createdAt === null` to determine if story needs generation
  - This triggers the call to `/chat/async` for new story creation
  - Location: `platform-api/src/routes/users_auth.py:1065-1072`
- ✅ **POST /chat/async** - Initiate story generation (returns WebSocket address for streaming)
  - Note: Previously documented as "POST /prompt" but actual endpoint is /chat/async
  - Body: Story configuration, user config params, tags, source IDs, project ID
  - Used by: Story creation workflow
  - Location: `platform-api/src/routes/users_auth.py:1150`
  - Database: Creates story record via `clj-pg-wrapper/src/routes/stories.py:107`

## Pending Migrations 🚧

### Story Management
**Priority: HIGH** - Core functionality for story viewing

- ❌ **GET /list** - List user stories
  - Query params: `sources=true` (include source attribution)
  - Used by: Dashboard, story list views
  - Location: `gofapi/src/clj/gofapi/stories/routes.clj`

### Tako Charts/Visualizations
**Priority: MEDIUM** - Data visualization features

- ❌ **GET /v2** - Get Tako chart preview link
  - Query params: `orgid=<uuid>&erid=<uuid>&l=...`
  - Used by: Chart/visualization rendering
  - Location: `gofapi/src/clj/gofapi/tako/routes.clj`

### Additional Story Endpoints
**Priority: LOW-MEDIUM** - Extended story functionality

- ❌ **GET /story/events** - Get events for specific story (alternate route)
- ❌ **POST /stories** - Create new story
- ❌ **PATCH /stories/:id** - Update story
- ❌ **DELETE /stories/:id** - Delete story
- ❌ **GET /stories/:id/versions** - Get story versions

### Credits System
**Priority: LOW** - Usage tracking (may use DynamoDB directly)

- ❌ **GET /credits** - Get user credit balance
- ❌ **POST /credits/deduct** - Deduct credits for operations

### Sources & Attribution
**Priority: LOW** - Source management for generated content

- ❌ **GET /sources** - List sources for organization
- ❌ **POST /sources** - Add source
- ❌ **DELETE /sources/:id** - Remove source

## Migration Strategy

### Phase 1: Core Story Functionality (Current Blocker)
Focus on endpoints needed for basic story generation and viewing:
1. **GET /list** - Users need to see their stories
2. **GET /mini** - Users need to preview stories
3. **POST /prompt** - Users need to create stories
4. **GET /events** - Users need to see story activity

**Estimated Effort**: 2-3 days
- Story schema/models in DynamoDB or Postgres
- Story generation integration with capitol-llm
- Event logging system

### Phase 2: Visualizations & Charts
1. **GET /v2** - Tako chart rendering

**Estimated Effort**: 1-2 days
- Chart generation service integration
- URL generation and signing

### Phase 3: Extended Functionality
1. Story CRUD operations (create, update, delete)
2. Version management
3. Source attribution

**Estimated Effort**: 2-3 days

### Phase 4: Credits & Metering
1. Credit balance management
2. Usage tracking
3. Deduction logic

**Estimated Effort**: 1-2 days

## Technical Considerations

### Data Storage Migration
- **Stories**: Need to determine storage (DynamoDB vs Postgres via clj-pg-wrapper)
- **Events**: Likely OpenSearch or DynamoDB for event logging
- **Credits**: DynamoDB (possibly already migrated)

### Service Dependencies
- **capitol-llm**: Story generation backend
- **clj-pg-wrapper**: Postgres access for user/org data
- **OpenSearch**: Event logging, search functionality

### Authentication
All endpoints must support **dual authentication**:
1. **Foreign User Auth**: X-API-Key + X-User-ID headers
2. **Session Auth**: Cookie-based session (for backward compatibility)

### Foreign User Considerations
- Foreign users need isolated story storage per organization
- Credit tracking per organization (not individual foreign user)
- Events should track foreign user activity separately

## Database Schema Requirements

### Stories Table
```python
{
    "story_id": "uuid",
    "user_id": "uuid",  # Foreign or regular user
    "org_id": "uuid",   # Organization (for foreign users)
    "title": "string",
    "content": "text",
    "config": "json",   # Story plan configuration
    "status": "enum",   # draft, generating, completed, failed
    "sources": "json[]", # Source attribution
    "created_at": "timestamp",
    "updated_at": "timestamp"
}
```

### Story Events Table
```python
{
    "event_id": "uuid",
    "story_id": "uuid",
    "event_type": "string",  # created, updated, viewed, shared
    "user_id": "uuid",
    "metadata": "json",
    "timestamp": "timestamp"
}
```

## Testing Strategy

For each migrated endpoint:
1. ✅ Unit tests with foreign user auth
2. ✅ Unit tests with session auth
3. ✅ Integration tests with demo-proxy-app
4. ✅ Frontend integration tests
5. ✅ Performance benchmarking vs gofapi

## Rollout Plan

### Phase 1: Parallel Run (Safe)
- Both gofapi and platform-api running
- Traffic gradually shifted to platform-api
- Fallback to gofapi if issues arise

### Phase 2: Platform-API Primary
- Platform-api handles all new requests
- gofapi only for legacy support

### Phase 3: Deprecate gofapi
- Remove gofapi from infrastructure
- Complete migration

## Related Tickets

- **BE-955**: Foreign user authentication implementation (Current)
- **BE-XXX**: Story management migration (To be created)
- **BE-XXX**: Events system migration (To be created)
- **BE-XXX**: Tako charts migration (To be created)

## Questions & Decisions Needed

1. **Story Storage**: DynamoDB or Postgres?
   - Recommendation: DynamoDB for scalability, Postgres for relational queries

2. **Event Logging**: OpenSearch or DynamoDB?
   - Recommendation: OpenSearch (already used for guardrails failures)

3. **Credits System**: Migrate or keep in gofapi?
   - Recommendation: Migrate to DynamoDB (consistent with other resources)

4. **Migration Timeline**: Aggressive or conservative?
   - Current: Focus on story endpoints blocking frontend (Phase 1)
   - Defer: Charts, versions, advanced features

## Success Metrics

- ✅ All frontend flows work without gofapi
- ✅ Response times comparable to gofapi
- ✅ Foreign user auth works for all endpoints
- ✅ Zero data loss during migration
- ✅ Backward compatibility maintained
