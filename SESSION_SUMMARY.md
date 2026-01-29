# Demo Proxy App - Foreign User Authentication Implementation

## Session Summary

This document summarizes the work completed to set up the demo proxy application and implement foreign user authentication following the clj-services (gofapi) pattern. This is part of the **gofapi → platform-api migration** effort.

> **📋 See [GOFAPI_MIGRATION.md](./GOFAPI_MIGRATION.md)** for complete migration status and next steps

---

## 1. Application Setup

### Initial Configuration
- Started the demo-proxy-app using Docker Compose
- Configured the application to connect to local `platform-api` at `http://platform_api/public`
- Application runs on `http://localhost:8000`
- React demo frontend runs on `http://localhost:5174`

### API Key Generation
- Created internal API key in platform-api for demo organization
- Organization ID: `f6fffb00-8fbc-4ec4-8d6b-f0e01154a253`
- API Key: `cap-dev-OPJC6oTQ-ebB7xRdd-7xydxD0C-oYVbyOYl`
- Stored in `.env` file

### Justfile Commands
Created `justfile` with automated setup commands:
```bash
just setup          # Full setup (build + start + setup-demo)
just start          # Start the application
just setup-demo     # Create API key and configure
just start-react    # Start React frontend
just logs           # View logs
```

---

## 2. Architecture Discussion

### System Components

**Platform-API (DynamoDB):**
- Stores organizations and their admin users
- Manages API keys linked to organization IDs
- Public-facing API at `/public`

**clj-wrapper (Postgres):**
- Stores organizations and their end-users
- End-users are people who use the platform via API (not admins)
- Handles user authentication and session management

**Demo Proxy App:**
- Forwards requests from frontend to platform-api
- Adds authentication headers (`X-API-Key`, `X-User-ID`) following gofapi pattern

---

## 3. Foreign User Authentication Flow

### Architecture Pattern
Based on the foreign user pattern from clj-services (gofapi middleware):

1. **Client** sends `X-API-Key` (API key) + `X-User-ID` (foreign user ID)
2. **Platform-API** validates API key → gets `org_id` from DynamoDB
3. **Platform-API** calls clj-wrapper: `POST /api/v1/users/external`
   ```json
   {
     "api_client_id": "org_id",
     "api_external_id": "foreign_user_id"
   }
   ```
4. **clj-wrapper**:
   - Creates stub organization in Postgres if it doesn't exist
   - Looks up user via `organization_x_members` JOIN `users` WHERE `api_external_id = foreign_user_id`
   - Returns existing user OR creates new user + adds to organization
5. **Platform-API** returns user data to client

### Implementation Details

**Files Created:**
- `/platform-api/src/dependencies/external_user_auth.py` - Foreign user authentication middleware (follows gofapi pattern)
- Endpoint added to `/clj-wrapper/src/routes/users.py` - Get-or-create foreign user

**Key Features:**
- Automatic organization stub creation in clj-wrapper
- User lookup via organization membership table
- Support for multiple foreign users per organization
- Each foreign user ID creates a separate user account

---

## 4. Bug Fixes

### Issue 1: 404 Errors on `/user/current-user`
**Problem:** Request path was being double-prefixed with `/api`

**Original Flow:**
```
Browser → /proxy/api/capitolai/user/current-user
Vite → http://localhost:8000/api/v1/user/current-user
Demo Proxy → http://platform_api/public/api/v1/user/current-user ❌
```

**Fixed Flow:**
```
Browser → /proxy/api/capitolai/user/current-user
Vite → http://localhost:8000/api/user/current-user
Demo Proxy → http://platform_api/public/user/current-user ✓
```

**Changes:**
- Updated `demo-proxy-app/app/main.py` - removed `/api` from forward URL
- Updated `react-demo/vite.config.js` - changed target from `/api/v1` to `/api`

### Issue 2: clj-wrapper Crash
**Problem:** Pydantic validation error on startup
```
pydantic_core._pydantic_core.ValidationError: 1 validation error for Settings
mailchimp_api_key
  Extra inputs are not permitted
```

**Fix:** Added `MAILCHIMP_API_KEY` field to `/clj-wrapper/src/config.py`

### Issue 3: Foreign Key Violation on User Creation
**Problem:** User insert failing silently, causing organization membership insert to fail

**Root Cause:** Organization didn't exist in clj-wrapper's Postgres database

**Solution:** Implemented automatic stub organization creation:
```python
# Ensure organization exists in Postgres (create stub if not)
if not existing_org:
    new_org = Organization(
        id=org_id,
        name=f"External Org {org_id}",
        created_at=datetime.utcnow(),
        updated_at=datetime.utcnow()
    )
    session.add(new_org)
    await session.flush()
```

### Issue 4: X-User-ID Header Not Forwarding
**Problem:** Demo proxy was hardcoding `X-User-ID: '1'` instead of passing through incoming header

**Fix:** Updated `add_custom_headers()` function to accept and forward incoming headers (following gofapi pattern):
```python
def add_custom_headers(original_content_type=None, incoming_headers=None):
    headers = {"X-User-ID": USER_ID}  # Default

    # Pass through X-User-ID if provided
    if incoming_headers and "x-user-id" in incoming_headers:
        headers["X-User-ID"] = incoming_headers["x-user-id"]
```

---

## 5. Testing Results

### Successful User Creation
```bash
# User "1" (default)
curl http://localhost:8000/api/user/current-user -H "X-User-ID: 1"
# Returns: user c5706d31-95df-435e-bb1c-0f231340cb87

# User "user_jane_456"
curl http://localhost:8000/api/user/current-user -H "X-User-ID: user_jane_456"
# Returns: user b86a4c0a-9c12-4ead-b603-a0016429d24e
```

### Verification
- ✅ Foreign users are created with unique IDs following gofapi pattern
- ✅ Users are linked to organization via `organization_x_members`
- ✅ Subsequent requests return existing users
- ✅ Multiple foreign users can exist for same organization
- ✅ Stub organizations are created automatically in clj-wrapper

---

## 6. Key Files Modified

### Platform-API
- `src/dependencies/external_user_auth.py` (NEW)
- `src/dependencies/public_api_auth.py` (MODIFIED)
- `src/routes/users_auth.py` (MODIFIED)

### clj-wrapper
- `src/config.py` (MODIFIED - added MAILCHIMP_API_KEY)
- `src/routes/users.py` (MODIFIED - added external user endpoint)

### Demo Proxy
- `app/main.py` (MODIFIED - fixed routing, header forwarding)
- `justfile` (NEW)
- `README.md` (MODIFIED - added documentation)

### React Demo
- `react-demo/vite.config.js` (MODIFIED - fixed port and proxy path)
- `react-demo/.env` (NEW)

---

## 7. Configuration Files

### `.env` (Demo Proxy)
```
DOMAIN=https://aigrants.co/
API_URL=http://platform_api/public
API_KEY=cap-dev-OPJC6oTQ-ebB7xRdd-7xydxD0C-oYVbyOYl
```

### `docker-compose.yml` Updates
- Added `cap-multi-compose` network connection
- Enables communication with platform_api container

---

## 8. Migration Status & Next Steps

### ✅ Completed Endpoints (BE-955)

**Authentication & User Management:**
- `GET /user/current-user` - Foreign user authentication with stats fields
- `GET /user/membership/current-membership` - Subscription info (dual pathway)
- `GET /user/storyplan-config` - Format settings/storyplan configurations
- `GET /prompts` - Organization prompts by API key

**Guardrails:**
- `POST /configs/guardrails/check/prompt` - Prompt validation against org guardrails

**Infrastructure:**
- Environment validation (`check-env.sh`, `.env.sample`)
- Service orchestration (`just start-services`, `just stop-services`)
- Foreign user testing (`test-foreign-user.sh`)
- Frontend integration with local source (`file:../../frontend/react-lib`)

### 🚧 Pending Migrations (Next Phase)

**Priority 1: Story Management** (Blocking frontend)
- `GET /list` - List user stories
- `GET /mini` - Story mini view/preview
- `POST /prompt` - Create/trigger story generation
- `GET /events` - Story events/activity logs

**Priority 2: Visualizations**
- `GET /v2` - Tako chart rendering

**Priority 3: Extended Features**
- Story CRUD operations (create, update, delete, versions)
- Credits system
- Source attribution

> **📋 Complete details in [GOFAPI_MIGRATION.md](./GOFAPI_MIGRATION.md)**

### Technical Decisions Required

1. **Story Storage**: DynamoDB vs Postgres for story data?
2. **Event Logging**: OpenSearch vs DynamoDB for activity tracking?
3. **Migration Timeline**: Aggressive (2-3 weeks) vs Conservative (1-2 months)?

### Production Considerations

1. **Error Handling:**
   - Organization creation failure handling
   - Foreign user creation logging/monitoring
   - Rate limiting on user creation

2. **Security:**
   - API key rotation mechanism
   - Audit logging for foreign user access
   - IP whitelisting for API keys

3. **Performance:**
   - Response time parity with gofapi
   - Caching strategy for frequently accessed data
   - Connection pooling optimization

---

## Summary

Successfully implemented foreign user authentication for the demo proxy application, enabling API-based user creation and management. The implementation follows the clj-services (gofapi) pattern and maintains separation between admin users (in platform-api) and end-users (in clj-wrapper).

The system now supports:
- Dynamic foreign user creation via API key + user ID (using X-API-Key and X-User-ID headers)
- Automatic organization provisioning in clj-wrapper
- Seamless integration between platform-api and clj-wrapper
- Multiple foreign users per organization
- Full compatibility with gofapi middleware pattern
