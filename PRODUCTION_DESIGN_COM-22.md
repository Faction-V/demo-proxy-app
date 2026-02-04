# gofapi Migration to platform-api - Production Design Document

**Epic:** COM-21 - Deprecate clj-services for Politico / capitol.ai
**Task:** COM-22 - Proxy Demo App POC using platform-api
**Status:** Production Implementation
**Timeline:** 5 weeks
**Date:** February 3, 2026

---

## 🎥 Demo Video

Watch the POC walkthrough and demonstration: [Loom Demo](https://www.loom.com/share/88ac83881ab64fcfb05449a5086ac3f4)

---

## Table of Contents

1. [Problem Context](#1-problem-context)
2. [Solution Architecture - Authentication Flow](#2-solution-architecture---authentication-flow)
3. [POC Results - What We Proved](#3-poc-results---what-we-proved)
4. [Production Requirements - Remaining Work](#4-production-requirements---remaining-work)
5. [API Compatibility & Migration Plan](#5-api-compatibility--migration-plan)
6. [Testing & Quality Assurance](#6-testing--quality-assurance)
7. [Deployment & Operations](#7-deployment--operations)

---

## 1. Problem Context

**Current State:**

Capitol AI's customer-facing NPM package (`@capitol.ai/react`) currently connects directly to gofapi, a legacy Clojure service (clj-services). This architecture creates several problems:

**Technical Debt:**
- Clojure expertise is limited on the team, slowing development velocity
- Difficult to debug and maintain compared to Python codebase
- Testing and CI/CD pipelines are separate from modern services
- No shared authentication patterns with platform-api

**Customer Impact:**
- Politico and other customers depend on stable API endpoints
- Any changes to gofapi risk breaking customer integrations
- Limited observability makes troubleshooting customer issues difficult
- Cannot iterate quickly on customer-facing features

**Architectural Constraints:**
- Frontend and NPM package tightly coupled to gofapi URLs
- Cannot deprecate clj-services while customers depend on it
- No gradual migration path - it's all-or-nothing
- Backend improvements blocked by legacy service dependencies

**Business Goals:**
- Enable deprecation of clj-services and reduce maintenance burden
- Maintain 100% backward compatibility for existing customers
- Improve development velocity for customer-facing features
- Modernize tech stack without disrupting customer workflows

---

## 2. Solution Architecture - Authentication Flow

**The POC proved a middleware proxy pattern that maintains API compatibility while enabling backend migration.**

### Customer Integration Pattern

Customers like Politico integrate via their own backend servers, not directly from browsers. Their backend acts as a proxy:

```
[Customer Frontend (React NPM package)]
    ↓
[Customer Backend (Politico servers)]
    ↓ Authentication Headers:
      X-User-ID: "politico-user-123"
      X-API-Key: "cap-prod-XXXX..."
    ↓
[demo-proxy-app] → [platform-api]
```

**Why This Architecture:**
- Customer controls their frontend deployment and can add business logic
- We provide the React components via NPM package
- API keys are stored securely on customer backend (never exposed to browser)
- Each customer has their own API key tied to their organization

### Foreign User Authentication Flow

When a request arrives at platform-api with X-User-ID + X-API-Key headers:

**1. API Key Validation:** Look up key in DynamoDB internal_api_keys table
   - Verify key exists and is active
   - Extract `org_id` from key record

**2. Foreign User Resolution:** Call clj-pg-wrapper `/api/v1/users/external`
```python
POST /api/v1/users/external
{
  "api_client_id": "org-politico",  # From API key
  "api_external_id": "politico-user-123"  # From X-User-ID header
}
```
- If user doesn't exist, clj-pg-wrapper creates them
- Links user to organization
- Returns user UUID

**3. Caching:** Store result in-memory (5-min TTL)
- Cache key: `"{org_id}:{external_user_id}"`
- Prevents rate limiting from repeated lookups
- Invalidates after 5 minutes

**4. Request Processing:** Use resolved user context for authorization
```python
{
  "user_id": "internal-uuid-789",
  "org_id": "org-politico",
  "email": "foreign_user@external",
  "external_user": True
}
```

---

## 3. POC Results - What We Proved

**The POC successfully validated the proxy pattern approach by implementing 6 critical endpoints.**

### ✅ Fully Working Endpoints (3)

**1. POST `/chat/async` - Story Generation**
- Accepts story configuration and user prompt
- Auto-injects source IDs from database (10 most recent)
- Forwards to capitol-llm for LLM generation
- Returns `socketAddress` for WebSocket connection
- End-to-end latency: ~250ms (well under 500ms target)

**2. GET `/events` - Fetch Story Events**
- Retrieves story events from capitol-llm
- Transforms `socket_address` → `socketAddress` (camelCase for frontend compatibility)
- Returns event history for story rendering
- Supports both initial load and reconnection scenarios

**3. GET/POST `/user/feedback/thumbs` - Story Feedback**
- GET: Check if user already provided feedback for a story
- POST: Submit thumbs up/down feedback with optional comment
- Currently logs feedback (database integration needed for production)
- Validates authentication and returns feedback ID

### 📋 Endpoints Requiring Implementation (3)

**4. PATCH `/events/bulk` - Edit Story Content**
- Bulk update/delete story events
- Forwards to capitol-llm `/bulk_update/{story_id}`
- Structure documented but needs event_id field mapping

**5. POST `/sources/upload-source/sync` & `/file` - Upload Sources**
- Upload JSON/URL sources or PDF/image files
- Forward to clj-pg-wrapper for processing
- Trigger embedding generation
- Structure documented, needs testing

**6. POST `/chat/suggestions/block` - AI Editing**
- AI-assisted editing for specific story blocks
- Accepts block context and user instruction
- Returns AI-generated content suggestions
- Requires implementation and testing

---

## 4. Production Requirements - Remaining Work

**To achieve production readiness, we need to complete 3 unimplemented endpoints, upgrade infrastructure, and ensure 100% API compatibility.**

### A. Endpoint Implementation (3 endpoints)

**1. PATCH `/events/bulk` - Story Content Editing**
- **Requirement:** Users manually edit story content in Blocknote editor and save changes
- **Current State:** Endpoint exists but returns 500 error due to event structure mismatch
- **Issue:** capitol-llm expects `event_id` field that frontend doesn't provide
- **Solution:** Platform-api should generate event_ids for events missing them, or capitol-llm should make field optional
- **Testing:** Create story → edit content → save → verify changes persist

**2. POST `/sources/upload-source/sync` & `/file` - Source Upload**
- **Requirement:** Users upload documents (JSON, URLs, PDFs, images) as knowledge sources
- **Current State:** Endpoints created, forward to clj-pg-wrapper, untested
- **Dependencies:** clj-pg-wrapper source processing, embedding generation
- **Solution:** Test end-to-end flow, handle file size limits, validate formats
- **Testing:** Upload each file type → verify embedding generation → search functionality works

**3. POST `/chat/suggestions/block` - AI Block Editing**
- **Requirement:** Users select text block and ask AI for editing suggestions
- **Current State:** Endpoint signature defined but not implemented
- **Dependencies:** Context extraction (surrounding blocks), prompt construction
- **Solution:** Forward block context + user instruction to capitol-llm
- **Testing:** Select block → request edit → verify AI suggestions → apply changes

### B. Infrastructure Upgrades

**Redis Distributed Caching:**
- **Current:** In-memory cache (5-min TTL) works for single instance only
- **Production Need:** Multiple platform-api instances for high availability
- **Solution:** Deploy Redis cluster, migrate caching logic
- **Cache Strategy:** Same 5-min TTL, LRU eviction, monitor hit rates

**Monitoring & Observability:**
- **Metrics:** API latency, error rates, cache hit rates, authentication success/failure
- **Logging:** Structured logs with correlation IDs across services
- **Alerting:** Error rate thresholds, latency SLOs, service health checks
- **Tools:** DataDog/Sentry integration (existing platform-api setup)

**Source Selection UI:**
- **Current:** Demo auto-injects 10 most recent sources (not suitable for production)
- **Production Need:** Users must select which sources to use for story generation
- **Solution:** Build source picker component in NPM package
- **Features:** Search, filter by date/type, multi-select, pagination

---

## 5. API Compatibility & Migration Plan

**Production deployment requires 100% backward compatibility with gofapi. Customers update only their API base URL - no code changes.**

### A. API Compatibility Requirements

**Request Format Compatibility:**
- Accept both snake_case and camelCase field names (frontend sends both)
- Support kebab-case in URLs (`story-id`, `source-ids`)
- Preserve exact gofapi authentication header requirements
- Match gofapi timeout behavior and error response formats

**Response Format Compatibility:**
- Transform snake_case responses from capitol-llm to camelCase for frontend
- Example: `socket_address` → `socketAddress` (already implemented in `/events`)
- Match gofapi status codes (200, 400, 401, 404, 500, 502)
- Preserve error detail message formats customers may depend on

**Behavioral Compatibility:**
- Same payload structures for all 6 endpoints
- Identical validation rules (required fields, field types)
- Same rate limiting behavior (per organization)
- Maintain WebSocket connection patterns

### B. Customer Migration Strategy

**Phase 1: Parallel Deployment (Week 1-2)**
- Deploy demo-proxy-app + platform-api to production
- Both old gofapi and new proxy infrastructure running
- Configure load balancer/DNS for traffic switching capability
- No customer traffic yet - internal testing only

**Phase 2: Internal Testing (Week 3)**
- Capitol AI team routes test traffic through new infrastructure
- Validate all 6 endpoints work correctly
- Monitor errors, latency, cache performance
- Verify authentication flow with test API keys

**Phase 3: Gradual Traffic Migration (Week 4)**
- **DNS/Load Balancer Cutover:** Point gofapi.capitol.ai to demo-proxy-app
- **Customers experience ZERO disruption** - same URL, no action required
- Gradual rollout options:
  - Start with 10% traffic → 25% → 50% → 100%
  - OR: Beta customers first, then all traffic
- Monitor customer-specific metrics in real-time
- **Rollback:** Switch DNS/load balancer back to old infrastructure if issues detected

**Customer Communication (Optional):**
```
Subject: Backend Infrastructure Upgrade - No Action Required

We've upgraded our backend infrastructure for improved
performance and reliability.

URL: No change - continue using https://gofapi.capitol.ai/api/v1
Action Required: None - fully backward compatible
Impact: Improved performance, same API contract
```

**Phase 4: Deprecation (Week 5)**
- All traffic successfully migrated to new infrastructure
- Monitor for 7 days to ensure stability
- Shutdown old gofapi service
- Archive clj-services codebase

---

## 6. Testing & Quality Assurance

**Production requires comprehensive testing across all 6 endpoints to ensure reliability and backward compatibility.**

### A. Unit Testing (Target: 80% Coverage)

**Backend Tests (platform-api):**
```python
# Authentication caching
test_cache_hit_returns_cached_data()
test_cache_miss_calls_clj_pg_wrapper()
test_expired_cache_refreshes()
test_invalid_api_key_returns_401()

# Endpoint validation
test_chat_async_requires_story_id()
test_events_bulk_validates_payload()
test_source_upload_handles_file_types()

# Response transformation
test_socket_address_transforms_to_camelcase()
test_error_responses_match_gofapi_format()
```

**Frontend Tests (NPM package):**
```typescript
// WebSocket connection
test_establishes_connection_with_socketAddress()
test_handles_connection_failure_with_retry()

// API calls
test_generateStory_posts_to_chat_async()
test_uploadSource_sends_multipart_form()
```

### B. Integration Testing

**End-to-End Flows:**
1. **Story Generation:** Create story → WebSocket connect → receive events → render
2. **Story Editing:** Load story → edit content → save → verify persistence
3. **Source Upload:** Upload document → embedding generation → use in story
4. **Foreign User Auth:** New user → auto-creation → cached lookup → subsequent requests

**Test Scenarios:**
```python
@pytest.mark.integration
async def test_full_story_generation_flow():
    # 1. Authenticate with API key
    # 2. POST /chat/async
    # 3. Verify socketAddress returned
    # 4. GET /events - verify story created
    # 5. Check cache hit on second request
```

### C. Load & Performance Testing

**Targets:**
- API endpoint latency: < 500ms (p95)
- WebSocket connection time: < 2 seconds
- Cache hit ratio: > 80%
- Concurrent users: 100+ simultaneous story generations

**Load Test (k6):**
```javascript
export let options = {
  stages: [
    { duration: '2m', target: 50 },   // Ramp up
    { duration: '5m', target: 100 },  // Sustained load
    { duration: '2m', target: 0 },    // Ramp down
  ],
};
```

### D. Compatibility Testing

**gofapi Parity Validation:**
- Side-by-side comparison: Same request to gofapi vs proxy
- Verify identical responses (modulo timestamps)
- Test all 6 endpoints with real customer payloads
- Validate error scenarios match gofapi behavior

**Backward Compatibility Checklist:**
- ✅ Request format (snake_case, camelCase, kebab-case)
- ✅ Response format (field names, data types)
- ✅ Status codes (200, 400, 401, 500, 502)
- ✅ Error messages (detail strings)
- ✅ Authentication headers (X-User-ID, X-API-Key)
- ✅ Timeout behavior

---

## 7. Deployment & Operations

**Production deployment requires zero-downtime rollout, comprehensive monitoring, and clear incident response procedures.**

### A. Infrastructure Requirements

**Redis Cluster:**
- High-availability setup (3+ nodes)
- Memory: 4GB minimum (accommodate growth)
- Eviction policy: LRU (Least Recently Used)
- Persistence: AOF (Append-Only File) for cache recovery
- Monitoring: Memory usage, hit rate, eviction rate

**Load Balancing:**
- Multiple platform-api instances (3+ for HA)
- Health check endpoint: `GET /health`
- Session affinity: Not required (stateless except Redis)
- SSL termination at load balancer

**Service Dependencies:**
- clj-pg-wrapper: Foreign user creation
- capitol-llm: Story generation, events
- DynamoDB: API key validation
- PostgreSQL (clj_postgres): Source queries

### B. Monitoring & Alerting

**Key Metrics:**
```
API Performance:
- Request latency (p50, p95, p99)
- Error rate by endpoint
- Requests per second

Authentication:
- Cache hit rate (target: >80%)
- Foreign user creation rate
- API key validation failures

System Health:
- Redis connection pool status
- Database connection health
- Capitol-llm availability
```

**Alerts:**
```
Critical (Page on-call):
- Error rate > 5% for 5 minutes
- API latency p95 > 2 seconds
- Redis unavailable

Warning (Slack notification):
- Cache hit rate < 70%
- High API key validation failures
- Elevated capitol-llm latency
```

### C. Incident Response

**Rollback Procedure:**
1. Customer reports issue via support channel
2. Verify issue specific to new proxy (check gofapi works)
3. Customer reverts API URL to gofapi
4. Engineering investigates root cause
5. Deploy fix and re-migrate customer

**Common Issues & Solutions:**
```
Issue: WebSocket connection fails
- Check socket-llm service health
- Verify socketAddress format in response
- Check network/firewall rules

Issue: Authentication failures spike
- Verify Redis availability
- Check clj-pg-wrapper rate limits
- Validate API key table integrity

Issue: Slow response times
- Check capitol-llm latency
- Verify Redis cache hit rate
- Scale platform-api instances if needed
```

### D. Timeline & Milestones (5 Weeks)

**Week 1: Implementation & Testing (Parallel)**
- Implement 3 remaining endpoints (events/bulk, sources/upload, chat/suggestions/block)
- Deploy Redis cluster
- Unit tests + integration tests (concurrent with implementation)

**Week 2: Validation & Staging**
- Load testing (100 concurrent users)
- gofapi compatibility validation
- Deploy to staging environment
- Internal team testing

**Week 3: Beta & Production Prep**
- Beta customer testing (1-2 low-traffic customers)
- Fix any issues discovered
- Production deployment ready

**Week 4: Production Rollout**
- Politico migration (day 1-2, monitor closely)
- Remaining customers (day 3-7, aggressive rollout)
- All customers migrated by end of week

**Week 5: Deprecation**
- Short 7-day grace period
- Shutdown gofapi
- Complete clj-services deprecation

---

## Appendix

### Related Links

**Jira:**
- Epic: [COM-21 - Deprecate clj-services](https://capitolai.atlassian.net/browse/COM-21)
- Task: [COM-22 - Proxy Demo App POC](https://capitolai.atlassian.net/browse/COM-22)

**Repositories:**
- demo-proxy-app: https://github.com/Faction-V/demo-proxy-app (Branch: BE-955-proxy-demo-app-poc)
- platform-api: https://github.com/Faction-V/platform-api (Branch: BE-955-proxy-demo-app-poc)
- frontend: https://github.com/Faction-V/frontend (Branch: features-test-branch)

**Demo:**
- Loom Walkthrough: https://www.loom.com/share/88ac83881ab64fcfb05449a5086ac3f4

### Key Commits

**demo-proxy-app:**
- `5382ce2` - [BE-955] feat(proxy): implement auto source ID injection

**platform-api:**
- `71529a1` - [BE-955] feat(api): add gofapi-compatible endpoints and foreign user auth

**frontend:**
- `c6bd0c893` - fix(react-lib): add comprehensive logging and null safety

---

**Document Status:** Ready for Production Implementation
**Next Review:** After Week 2 staging deployment
**Last Updated:** February 3, 2026
