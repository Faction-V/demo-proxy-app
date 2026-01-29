# Session Summary - Foreign User Auth & Events Endpoint Migration

## Work Completed

### `/events` Endpoint Migration ✅

Successfully migrated the `GET /events` endpoint from gofapi to platform-api.

**Endpoint Details:**
- **Path**: `/capitolai/events` (mounted under `/public` prefix)
- **Full URL**: `http://platform_api/public/capitolai/events`
- **Query Parameters**: `story-id` (UUID, required)
- **Headers**:
  - `X-User-ID`: Foreign user identifier
  - `X-API-Key`: Organization API key
  - `X-Organization-ID`: Sent to capitol-llm (extracted from API key)

**Implementation Notes:**
1. Validates foreign user authentication via X-API-Key + X-User-ID
2. Transforms `story-id` → `external_id` for capitol-llm
3. Sends `org_id` as `X-Organization-ID` header (not query param)
4. Returns response with cache control headers matching gofapi

**Key Technical Discoveries:**
- gofapi route structure: `/api/{api-version-string}/events`
- Frontend uses "capitolai" as the api-version-string: `/api/capitolai/events`
- Capitol-llm expects `external_id` as query param and `X-Organization-ID` as header
- gofapi's `parse-params` transforms `story-id` → `external-id` (snake_case)
- gofapi's `capitol-json-headers` adds `X-ORGANIZATION-ID` header

## Issues Resolved

### 1. Capitol-LLM Not Running
**Problem**: Connection refused to capitol-llm
**Root Cause**: Local redis-server on port 6379 blocked docker redis
**Fix**: Killed local redis-server (PID 7319)

### 2. Wrong Directory Path
**Problem**: justfile referenced `/capitol-llm` but correct path is `/llm`
**Fix**: Updated justfile line 7 to use `/llm` directory

### 3. Parameter Naming
**Problem**: Capitol-llm validation error - expected `external_id`, got `story-id`
**Fix**: Changed query param from `story-id` to `external_id`

### 4. Parameter Placement
**Problem**: Sending `org-id` as query parameter
**Fix**: Moved `org-id` to `X-Organization-ID` header matching gofapi pattern

### 5. Endpoint Path
**Problem**: Created endpoint at `/events` but frontend hits `/capitolai/events`
**Fix**: Changed endpoint path to `/capitolai/events`

## Outstanding Issues

### Capitol-LLM Database Tables Missing ⚠️
**Status**: Not blocking endpoint migration
**Details**: Capitol-llm database is missing `event` and `request_info` tables
**Error**: `relation "event" does not exist`
**Impact**: Endpoint works correctly but capitol-llm returns 500
**Action Needed**: Run capitol-llm database migrations

## Files Modified

1. **platform-api/src/routes/users_auth.py** (lines 852-954)
   - Added GET `/capitolai/events` endpoint
   - Implements foreign user auth
   - Proxies to capitol-llm with correct parameters and headers

2. **demo-proxy-app/justfile** (line 7)
   - Fixed `capitol_llm_dir` path from `/capitol-llm` to `/llm`

3. **demo-proxy-app/GOFAPI_MIGRATION.md**
   - Marked `/events` endpoint as completed

## Testing Status

**Endpoint Connectivity**: ✅ Working
- Platform-api receives requests correctly
- Forwards to capitol-llm successfully
- Headers and parameters formatted correctly

**Capitol-LLM Integration**: ⚠️ Partial
- Capitol-llm receives `external_id` query parameter ✅
- Capitol-llm receives `X-Organization-ID` header ✅
- Database tables missing (infrastructure issue) ❌

**Test Command**:
```bash
curl "http://localhost:8000/api/capitolai/events?story-id=<uuid>" \
  -H "X-User-ID: john@example.com" \
  -H "X-API-Key: <api-key>"
```

**Expected**: 500 error from capitol-llm (database tables missing)
**Actual**: 500 error from capitol-llm (database tables missing) ✅

## Next Steps

### Immediate (Capitol-LLM Infrastructure)
1. Run capitol-llm database migrations to create `event` and `request_info` tables
2. Verify endpoint works end-to-end with valid story data

### Phase 1: Core Story Endpoints (Priority: HIGH)
From GOFAPI_MIGRATION.md - still pending:
1. **GET /list** - List user stories
2. **GET /mini** - Get story mini view
3. **POST /prompt** - Create/trigger story generation

These are blocking frontend story functionality.

## Architecture Patterns Established

### Foreign User Authentication Flow
```
1. Client sends X-User-ID + X-API-Key headers
2. Platform-api validates API key via clj-pg-wrapper
3. Platform-api creates/retrieves foreign user
4. Platform-api extracts org_id from API key
5. Platform-api forwards request with org context
```

### Capitol-LLM Integration Pattern
```
1. Transform gofapi query params (story-id → external_id)
2. Send external_id as query parameter
3. Send org_id as X-Organization-ID header
4. Return response with cache control headers
```

### URL Path Structure
```
Frontend: /api/capitolai/<endpoint>
Proxy: forwards to platform_api/public/capitolai/<endpoint>
Platform-API: /public/capitolai/<endpoint> (via router mount)
```

## Lessons Learned

1. **Check gofapi route structure** - The api-version-string pattern wasn't immediately obvious
2. **Headers vs Query Params** - Study gofapi's middleware functions to understand parameter handling
3. **Service dependencies** - Ensure all services (redis, capitol-llm, etc.) are running before testing
4. **Database state** - Infrastructure issues (missing tables) can block endpoint testing
5. **Path prefixes** - Frontend may use non-obvious version strings ("capitolai" instead of "v1")
