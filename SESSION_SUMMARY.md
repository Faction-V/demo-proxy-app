# Session Summary: Foreign User Authentication Flow

## Overview
Fixed the complete authentication flow for foreign users accessing `/organizations/me` via JWT tokens.

## Authentication Flow

### 1. Get JWT Token
**Endpoint**: `POST /user/current-token`
- **Input**: X-User-ID + X-API-Key headers
- **Output**: JWT token with 30-day expiration
- **Token Payload**: 
  ```json
  {
    "sub": "user-uuid",
    "org_id": "organization-uuid",
    "exp": timestamp
  }
  ```

### 2. Use JWT Token
**Endpoint**: `GET /organizations/me`
- **Input**: X-User-Token header with JWT
- **Output**: List of organizations the user belongs to

## Changes Made

### 1. `/user/current-token` Endpoint
**File**: `platform-api/src/routes/users_auth.py:384`

**Changes**:
- Replaced old proxy endpoint with foreign auth implementation
- Fixed duplicate endpoint registration issue
- **Key Enhancement**: Added `org_id` to JWT token payload for foreign users
- This eliminates need to query database when validating JWT tokens

**Code**:
```python
jwt_token = create_access_token(
    data={"sub": str(user_uuid), "org_id": org_id},
    expires_delta=timedelta(days=30)
)
```

### 2. `check_org_access` Dependency
**File**: `platform-api/src/dependencies/public_api_auth.py:173`

**Changes**:
- Added support for foreign user authentication (X-User-ID + X-API-Key)
- Added JWT token decoding for self-generated tokens
- Extracts `org_id` from JWT payload for foreign users
- Falls back to external Auth0 validation for non-self-generated tokens

**Flow**:
1. Try foreign user auth (X-User-ID + X-API-Key) first
2. If not present, try decoding JWT token locally
3. If JWT decoding succeeds and has `org_id`, treat as foreign user
4. Otherwise, validate with external Auth0 service

### 3. `/organizations/me` Endpoint
**File**: `platform-api/src/routes/organizations.py:70`

**Changes**:
- Made async to support validation functions
- Added dual authentication support:
  - X-User-ID + X-API-Key headers
  - X-User-Token header with JWT
- Returns user's organization directly for foreign users
- Falls back to org membership lookup for regular users

## Testing

### Direct API Tests
```bash
# Get token
curl -X GET 'http://localhost:8811/public/user/current-token' \
  -H "X-User-ID: 1" \
  -H "X-API-Key: cap-dev-OPJC6oTQ-ebB7xRdd-7xydxD0C-oYVbyOYl"

# Use token
curl -X GET 'http://localhost:8811/public/organizations/me' \
  -H "X-User-Token: <token>"
```

### Frontend Proxy Tests
```bash
# Get token
curl -X GET 'http://localhost:5174/proxy/capitolai/api/v1/user/current-token' \
  -H "X-User-ID: 1" \
  -H "X-API-Key: cap-dev-OPJC6oTQ-ebB7xRdd-7xydxD0C-oYVbyOYl"

# Use token
curl -X GET 'http://localhost:5174/proxy/platform/organizations/me' \
  -H "X-User-Token: <token>"
```

## Migration Document Updated

**File**: `demo-proxy-app/GOFAPI_MIGRATION.md`

Added to completed migrations:
- ✅ `GET /user/current-token` - JWT authentication token (30-day expiration)
- ✅ `GET /organizations/me` - User's organizations (supports JWT tokens)

## Key Design Decisions

### Why Include org_id in JWT Token?
**Problem**: Foreign users don't exist in the regular `users` table, they're in the `foreign_user` table. Looking them up by UUID returns 404.

**Solution**: Include `org_id` in the JWT token payload so we don't need database lookups when validating the token. This:
- Eliminates database queries
- Improves performance
- Simplifies error handling
- Makes the token self-contained

### Why Not Use External Auth Service?
Self-generated JWT tokens are validated locally because:
1. External Auth0 service doesn't recognize our tokens
2. We control the secret key and can validate securely
3. Faster validation (no external HTTP call)
4. Works offline/in isolated environments

## Files Modified

1. `/Users/johnkealy/srv/capitol/platform-api/src/routes/users_auth.py`
2. `/Users/johnkealy/srv/capitol/platform-api/src/dependencies/public_api_auth.py`
3. `/Users/johnkealy/srv/capitol/platform-api/src/routes/organizations.py`
4. `/Users/johnkealy/srv/capitol/demo-proxy-app/GOFAPI_MIGRATION.md`

## Status

✅ **Complete**: Both endpoints fully functional with JWT token authentication flow
✅ **Tested**: Works via direct API and frontend proxy
✅ **Documented**: Migration document updated

---

## Story Creation Flow Investigation & Fix

### Problem Discovery
After implementing JWT authentication, discovered that `/chat/async` endpoint wasn't being triggered by the frontend for new story creation.

### Root Cause Analysis

**Investigation Steps**:
1. Examined frontend code in `/Users/johnkealy/srv/capitol/frontend/web/src/app/hooks/useCreateDocument.tsx:253`
   - Found `/chat/async` POST call in `createNewStory()` function
2. Traced call chain to `/Users/johnkealy/srv/capitol/frontend/web/src/app/story/components/EditorStory/EditorStory.tsx:243`
   - Discovered critical conditional: `if (miniStory.createdAt === null)`
   - This check determines whether to call `createNewStory()` for new stories

**The Root Cause**:
- `/stories/mini` endpoint was returning 404 for non-existent stories
- Frontend treats 404 as error and stops processing
- Frontend needs to check `createdAt === null` to determine if story is new
- Initial fix returning `{}` made `createdAt` undefined, not null
- JavaScript: `undefined === null` evaluates to `false`
- Result: `createNewStory()` never called, `/chat/async` never triggered

### Solution Implementation

**File**: `platform-api/src/routes/users_auth.py:1065-1072`

**Final Fix**:
```python
# If story doesn't exist in database (404), return minimal object for new story
# Frontend checks createdAt === null to determine if story needs generation
if db_response.status_code == 404:
    logger.info(f"Story {story_id} not found in database, returning minimal object with createdAt=null")
    return JSONResponse(
        content={"createdAt": None},  # None serializes to null in JSON
        status_code=200
    )
```

**Why This Works**:
1. Returns HTTP 200 (not 404) so frontend continues processing
2. Returns `{"createdAt": null}` which makes `createdAt` explicitly `null` (not undefined)
3. Frontend check `miniStory.createdAt === null` evaluates to `true`
4. Triggers `createNewStory()` function
5. Successfully calls `/chat/async` to generate story

### Testing

**Direct API Test**:
```bash
curl 'http://localhost:8811/public/stories/mini?story-id=test-new-story' \
  -H "X-User-ID: 1" \
  -H "X-API-Key: cap-dev-OPJC6oTQ-ebB7xRdd-7xydxD0C-oYVbyOYl"

# Response: {"createdAt": null}
```

**Frontend Proxy Test**:
```bash
curl 'http://localhost:5174/proxy/capitolai/api/stories/mini?story-id=another-test' \
  -H "X-User-ID: 1" \
  -H "X-API-Key: cap-dev-OPJC6oTQ-ebB7xRdd-7xydxD0C-oYVbyOYl"

# Response: {"createdAt": null}
```

### Complete Story Creation Flow

Now the flow works end-to-end:

1. **User initiates story creation** → Frontend generates new UUID
2. **Frontend calls** `GET /stories/mini?story-id=<uuid>`
   - Backend checks database
   - Story doesn't exist (404 from database)
   - Returns `{"createdAt": null}` with HTTP 200
3. **Frontend receives** `{"createdAt": null}`
   - Checks `if (miniStory.createdAt === null)` → `true`
   - Calls `createNewStory()` function
4. **createNewStory() executes**
   - Calls `POST /chat/async` with story configuration
   - Receives WebSocket address for streaming
5. **Story generation begins** via capitol-llm service

### Key Learnings

1. **JavaScript null vs undefined**: Critical difference in frontend conditionals
   - `undefined === null` is `false`
   - Must explicitly return `null` value, not omit property
2. **Frontend-Backend Contract**: Understanding exact response format expectations
3. **Error Flow vs Success Flow**: 404 stops processing, 200 continues with data
4. **Database Abstraction**: Backend can transform "not found" into valid business logic response

### Files Modified

1. `/Users/johnkealy/srv/capitol/platform-api/src/routes/users_auth.py` (lines 1065-1072)

### Status

✅ **Complete**: Story creation flow fully functional
✅ **Tested**: Both direct API and frontend proxy confirmed working
✅ **Root Cause**: Identified and documented
✅ **Solution**: Implemented and verified
