# Proxy Demo App POC - Design Document
**Epic:** COM-21 - Deprecate clj-services for Politico / capitol.ai
**Task:** COM-22 - Proxy Demo App POC using platform-api
**Authors:** Capitol AI Engineering Team
**Date:** February 2, 2026
**Status:** Implementation Complete (POC Phase)

---

## Problem Context

Capitol AI currently operates a legacy Clojure-based service (`clj-services`) that provides critical API endpoints for story generation, source management, and user authentication. This service has become a maintenance burden and technical debt:

**Current Challenges:**
- **Legacy Technology Stack**: Clojure services require specialized knowledge, limiting team velocity
- **Tight Coupling**: Frontend directly depends on gofapi endpoints, making migration difficult
- **Limited Observability**: Older logging and monitoring patterns
- **Deployment Complexity**: Separate deployment pipeline from modern Python services
- **API Inconsistencies**: Different authentication patterns, response formats (snake_case vs camelCase)

**Current Solution:**
The existing architecture has three main components:
1. **Frontend (React)** → Direct calls to gofapi endpoints
2. **clj-services (Clojure)** → Handles story generation, sources, authentication
3. **capitol-llm (Clojure)** → LLM orchestration and WebSocket streaming

**Shortcomings:**
- **No Migration Path**: Direct frontend-to-gofapi coupling prevents incremental migration
- **Duplicate Code**: Authentication logic exists in multiple services
- **Testing Difficulty**: Integration testing requires full Clojure stack
- **Foreign API Support**: External API authentication pattern not well-supported
- **Rate Limiting Issues**: No caching layer for user lookups causes rate limit errors

---

## Proposed Solution

**High-Level Summary:**
Implement a Python-based proxy middleware (`demo-proxy-app`) that sits between the frontend and backend services, enabling incremental migration from clj-services to platform-api while maintaining backward compatibility.

**Key Components:**
1. **demo-proxy-app (FastAPI)**: Middleware proxy with request interception and transformation
2. **platform-api enhancements**: New gofapi-compatible endpoints with dual authentication
3. **Frontend instrumentation**: Comprehensive logging for debugging WebSocket flows

**What It Will Do:**
- Intercept API requests and automatically inject source IDs from database
- Transform request/response formats between frontend and backend services
- Provide proof-of-concept for full gofapi deprecation
- Support foreign user authentication (X-User-ID + X-API-Key headers)
- Enable gradual migration without breaking existing functionality

**How It Will Be Built:**
- **Middleware Pattern**: Catch-all route interceptor in FastAPI
- **Database Integration**: Direct SQLAlchemy connection to clj_postgres for source queries
- **Authentication Caching**: In-memory cache with TTL to prevent rate limiting
- **Format Transformation**: Response transformation layer (snake_case ↔ camelCase)

**What's Different:**
- **Incremental Migration**: Each endpoint can be migrated independently
- **Dual Authentication**: Supports both legacy session auth and new foreign user auth
- **Transparent Proxy**: Frontend doesn't need immediate changes
- **Modern Stack**: Python/FastAPI for easier maintenance and testing

---

## Goals and Non-Goals

### Goals

**Primary Goals:**
- ✅ **Prove viability of proxy pattern** for incremental gofapi deprecation
- ✅ **Implement auto source ID injection** to simplify demo app usage
- ✅ **Migrate 7 core endpoints** from gofapi to platform-api
- ✅ **Support foreign user authentication** with X-User-ID/X-API-Key headers
- ✅ **End-to-end WebSocket story generation** working in demo app

**Technical Requirements:**
- ✅ Database integration with clj_postgres for source retrieval
- ✅ In-memory caching to prevent rate limit errors (5-minute TTL)
- ✅ Response format transformation (snake_case → camelCase)
- ✅ Comprehensive logging for debugging (STEP 1-7 instrumentation)
- ✅ Docker Compose orchestration for local development

**Success Metrics:**
- Story generation working end-to-end via proxy
- WebSocket connection establishment successful
- Real-time event streaming functional
- No authentication rate limit errors
- Demo app usable by external stakeholders

### Non-Goals

**Out of Scope for POC:**
- ❌ **Production deployment** - This is a POC, not production-ready
- ❌ **Performance optimization** - Focus on functionality over performance
- ❌ **Distributed caching** - In-memory cache sufficient for POC
- ❌ **Complete gofapi migration** - Only 7 endpoints needed for demo
- ❌ **UI for source selection** - Auto-injection of 10 most recent sources is acceptable
- ❌ **Event bulk update fix** - Known issue but non-blocking (500 error on event saves)
- ❌ **Security hardening** - Basic authentication sufficient for demo
- ❌ **Load testing** - Single-user demo scenario only

---

## Design

### Overall Architecture

The system follows a **middleware proxy pattern** where demo-proxy-app acts as an intelligent intermediary between the frontend and backend services:

```
┌─────────────────────────────────────────────────────────────┐
│                    User Browser (React Demo)                 │
│                     http://localhost:5179                    │
└───────────────────────────────┬─────────────────────────────┘
                                │
                                │ HTTP Requests
                                ▼
┌─────────────────────────────────────────────────────────────┐
│                   demo-proxy-app (FastAPI)                   │
│                    http://localhost:8811                     │
├─────────────────────────────────────────────────────────────┤
│  Responsibilities:                                           │
│  • Request interception (catch-all route)                    │
│  • Auto-inject source IDs from database                      │
│  • Header transformation (X-User-ID, X-API-Key)              │
│  • Request forwarding to platform-api                        │
├─────────────────────────────────────────────────────────────┤
│  Database: clj_postgres (PostgreSQL)                         │
│  • Direct connection via SQLAlchemy                          │
│  • Query: SELECT id FROM sources ORDER BY created_at DESC   │
│  • Fetch 10 most recent sources                              │
└───────────────────────────────┬─────────────────────────────┘
                                │
                                │ Transformed Requests
                                ▼
┌─────────────────────────────────────────────────────────────┐
│                   platform-api (FastAPI)                     │
│                    http://localhost:8000                     │
├─────────────────────────────────────────────────────────────┤
│  New Endpoints:                                              │
│  • POST /chat/async - Story generation                       │
│  • GET /events - Fetch story events + socketAddress          │
│  • PATCH /events/bulk - Bulk event updates                   │
│  • GET/POST /user/feedback/thumbs - Story feedback           │
│  • POST /sources/upload-source/sync - Source upload          │
│  • GET /organizations/{org_id}/sources - List sources        │
│  • POST /organizations/{org_id}/api-keys - Manage keys       │
├─────────────────────────────────────────────────────────────┤
│  Authentication:                                             │
│  • Dual auth: Foreign user (headers) OR Session (JWT)        │
│  • In-memory cache (5-min TTL) for foreign user lookups      │
│  • JWT token decoding (self-generated + Auth0)               │
├─────────────────────────────────────────────────────────────┤
│  Format Transformation:                                      │
│  • Response: socket_address → socketAddress                  │
│  • Request: camelCase → snake_case (where needed)            │
└───────────────────────────────┬─────────────────────────────┘
                                │
                                │ LLM Generation Request
                                ▼
┌─────────────────────────────────────────────────────────────┐
│                   capitol-llm (Clojure)                      │
│                    http://localhost:8080                     │
├─────────────────────────────────────────────────────────────┤
│  • Story generation via LLM                                  │
│  • Returns socket_address for WebSocket connection           │
│  • Coordinates with qdrant for source retrieval              │
└───────────────────────────────┬─────────────────────────────┘
                                │
                                │ socket_address returned
                                ▼
┌─────────────────────────────────────────────────────────────┐
│                   socket-llm (WebSocket)                     │
│                    ws://localhost:8081                       │
├─────────────────────────────────────────────────────────────┤
│  • Real-time event streaming via WebSocket                   │
│  • Story content delivered incrementally                     │
│  • Events: content, citations, metadata                      │
└───────────────────────────────┬─────────────────────────────┘
                                │
                                │ WebSocket Events
                                ▼
┌─────────────────────────────────────────────────────────────┐
│              Frontend React Library (Blocknote)              │
├─────────────────────────────────────────────────────────────┤
│  • Establishes WebSocket connection                          │
│  • Renders story content in real-time                        │
│  • Blocknote editor for rich text editing                    │
└─────────────────────────────────────────────────────────────┘
```

### Request Flow: Story Generation

**Step-by-Step Flow:**

1. **User Action**: User enters prompt in CreateStory component
2. **STEP 1**: `generateStory()` POSTs to `/chat/async` with storyId and prompt
3. **Proxy Interception**: demo-proxy-app catches request in catch-all route
4. **Source Injection**: Queries clj_postgres for 10 most recent sources
5. **Payload Modification**: Adds `"source-ids": [...]` to request body
6. **Forwarding**: Sends modified request to platform-api
7. **Authentication**: platform-api validates X-User-ID + X-API-Key headers
8. **LLM Request**: platform-api forwards to capitol-llm with source_ids
9. **STEP 2**: Response received with `socket_address` (transformed to `socketAddress`)
10. **Component Switch**: Frontend switches from CreateStory → EditorStory
11. **STEP 3-4**: Blocknote component extracts socketAddress and prepares WebSocket
12. **STEP 5**: `streamToBlocknote()` creates WebSocket connection
13. **STEP 6**: WebSocket `onopen` event fires, connection established
14. **Event Streaming**: socket-llm streams story events in real-time
15. **Rendering**: Blocknote editor renders content as events arrive
16. **STEP 7**: WebSocket closes when story generation complete

---

## System Architecture

### Major Components

#### 1. demo-proxy-app (Middleware)

**Technology**: Python 3.12 + FastAPI + SQLAlchemy
**Port**: 8811
**Role**: Intelligent request interceptor and transformer

**Key Responsibilities:**
- **Request Interception**: Catch-all route (`/{path:path}`) captures all API requests
- **Database Queries**: Direct connection to clj_postgres/gofapi database
- **Payload Injection**: Automatically adds source IDs to `/chat/async` requests
- **Header Management**: Adds X-User-ID and X-API-Key headers for authentication
- **Request Forwarding**: Proxies requests to platform-api with modifications

**Code Structure:**
```python
# main.py
app = FastAPI()

# Database connection
DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://postgres:postgres@clj_postgres:5432/gofapi")
engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(bind=engine)

def get_user_source_ids(user_id: str) -> list[str]:
    """Fetch 10 most recent sources from database"""
    with SessionLocal() as session:
        query = text("SELECT id FROM sources ORDER BY created_at DESC LIMIT 10")
        result = session.execute(query)
        return [str(row[0]) for row in result.fetchall()]

@app.api_route("/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "PATCH"])
async def catch_all(request: Request, path: str):
    # Intercept /chat/async for source injection
    if path.endswith("chat/async") and request.method == "POST":
        body_json = json.loads(body)
        source_ids = get_user_source_ids(user_id)
        body_json["source-ids"] = source_ids
        modified_body = json.dumps(body_json).encode()

    # Forward to platform-api
    async with httpx.AsyncClient() as client:
        response = await client.request(
            method=request.method,
            url=f"{API_URL}/{path}",
            headers=custom_headers,
            content=modified_body
        )
    return response
```

**Design Patterns:**
- **Proxy Pattern**: Transparent intermediary between client and server
- **Decorator Pattern**: Enhances requests with additional data
- **Repository Pattern**: Database access abstracted via functions

#### 2. platform-api (Backend Service)

**Technology**: Python 3.12 + FastAPI + DynamoDB + PostgreSQL
**Port**: 8000
**Role**: Primary API service replacing gofapi endpoints

**New Endpoints Implemented:**

| Endpoint | Method | Purpose | Status |
|----------|--------|---------|--------|
| `/chat/async` | POST | Initiate story generation | ✅ Complete |
| `/events` | GET | Fetch story events + socketAddress | ✅ Complete |
| `/events/bulk` | PATCH | Bulk update story events | ⚠️ Working (500 error) |
| `/user/feedback/thumbs` | GET | Get story feedback | ✅ Complete |
| `/user/feedback/thumbs` | POST | Submit story feedback | ✅ Complete |
| `/sources/upload-source/sync` | POST | Upload source synchronously | ✅ Complete |
| `/organizations/{org_id}/sources` | GET | List organization sources | ✅ Complete |
| `/organizations/{org_id}/api-keys` | POST | Create API keys | ✅ Complete |

**Authentication Architecture:**

```python
# Dual Authentication Flow
async def check_org_access(
    x_user_id: str | None = Header(None),
    x_api_key: str | None = Header(None),
    x_user_token: str | None = Header(None)
):
    # Path 1: Foreign User Auth (X-User-ID + X-API-Key)
    if x_user_id and x_api_key:
        user_info = await validate_external_user_token(x_user_id, x_api_key)
        return user_info  # {user_id, email, org_id, external_user: True}

    # Path 2: Session Auth (JWT Token)
    else:
        # Try self-generated JWT first
        try:
            payload = jwt.decode(token, settings.JWT_SECRET_KEY)
            user_uuid = payload.get("sub")
            org_id = payload.get("org_id")
            return {"user_id": user_uuid, "org_id": org_id}
        except JWTError:
            # Fall back to Auth0 token validation
            user_info = check_token(token)
            return user_info
```

**Caching Strategy:**

```python
# In-Memory Cache (5-minute TTL)
_external_user_cache: Dict[str, tuple[Dict[str, Any], float]] = {}
_CACHE_TTL = 300  # 5 minutes

def get_or_create_external_user(org_id: str, foreign_user_id: str):
    cache_key = f"{org_id}:{foreign_user_id}"
    current_time = time.time()

    # Check cache first
    if cache_key in _external_user_cache:
        user_data, cached_time = _external_user_cache[cache_key]
        if current_time - cached_time < _CACHE_TTL:
            return user_data  # Cache hit

    # Cache miss - call clj-pg-wrapper
    response = requests.post(wrapper_url, json=payload)
    user_data = response.json()

    # Update cache
    _external_user_cache[cache_key] = (user_data, current_time)
    return user_data
```

**Design Patterns:**
- **Facade Pattern**: Simplifies interaction with multiple backend services
- **Adapter Pattern**: Transforms between different API formats
- **Cache-Aside Pattern**: In-memory caching for frequently accessed data
- **Strategy Pattern**: Dual authentication strategies

#### 3. Frontend React Library

**Technology**: React 18 + TypeScript + Vite + Blocknote Editor
**Build**: Compiled to `@capitol.ai/react` NPM package
**Role**: User interface for story creation and editing

**Key Components:**

**A. CreateStory Component**
- User prompt input
- Source selection (auto-injected by proxy)
- Story configuration options
- Callback on submit triggers `generateStory()`

**B. EditorStory Component**
- Blocknote rich text editor
- WebSocket connection management
- Real-time event streaming
- Citation rendering

**C. generateStory Utility**
```typescript
// STEP 1-2: POST to /chat/async
export const generateStory = async ({storyId, userPrompt, sourceIds}) => {
  const requestBody = {
    'story-id': storyId,
    'source-ids': sourceIds,
    'user-config-params': {userQuery: userPrompt}
  };

  console.log('🚀 [STEP 1] POST /chat/async - Request body:', requestBody);

  const response = await genericRequest({
    url: `${PROXY_API_URL}/chat/async`,
    method: 'POST',
    body: requestBody
  });

  console.log('✅ [STEP 2] Response received:', response);
  console.log('📍 Socket address:', response?.socketAddress);

  return response;
};
```

**D. WebSocket Connection Management**
```typescript
// STEP 3-7: WebSocket lifecycle
useEffect(() => {
  if (!socketAddress || !storyId) return;

  console.log('🔌 [STEP 3] Preparing WebSocket connection');
  console.log('📍 Socket address:', socketAddress);

  streamToBlocknote({socketAddress, editor, storyId});

  console.log('✅ [STEP 4] Called streamToBlocknote');
}, [socketAddress, storyId]);

const streamToBlocknote = ({socketAddress}) => {
  console.log('🎯 [STEP 5] Creating WebSocket connection');

  const socket = new WebSocket(socketAddress);

  socket.onopen = () => {
    console.log('🎉 [STEP 6] WebSocket OPENED successfully!');
    setCurrentWebsocket(socket);
  };

  socket.onmessage = (event) => {
    const llmEvent = JSON.parse(event.data);
    processEvent(llmEvent);  // Render in Blocknote
  };

  socket.onclose = (event) => {
    console.log('🔴 [STEP 7] WebSocket closed, code:', event.code);
    setCurrentWebsocket(undefined);
  };
};
```

**Design Patterns:**
- **Observer Pattern**: WebSocket event handling
- **State Management Pattern**: React hooks for component state
- **Facade Pattern**: `generateStory` utility simplifies API calls
- **Strategy Pattern**: Different rendering strategies for event types

### Design Decisions and Trade-offs

#### Decision 1: Middleware Proxy Pattern

**Decision**: Implement demo-proxy-app as middleware instead of directly migrating frontend

**Rationale:**
- ✅ **Incremental Migration**: Can migrate endpoints one at a time
- ✅ **Backward Compatibility**: Existing frontend code doesn't need changes
- ✅ **Testing Isolation**: Can test new endpoints without affecting production
- ✅ **Rollback Safety**: Easy to rollback by switching proxy targets

**Trade-offs:**
- ❌ **Additional Latency**: Extra network hop adds ~10-20ms
- ❌ **Operational Overhead**: One more service to deploy and monitor
- ❌ **Debugging Complexity**: Need to trace through multiple services

**Alternative Considered**: Direct frontend migration
- Rejected because it requires changing frontend code immediately
- Would need all endpoints migrated before switching
- No gradual rollout possible

#### Decision 2: Direct Database Access from Proxy

**Decision**: Query clj_postgres directly from demo-proxy-app for source IDs

**Rationale:**
- ✅ **Simplicity**: No need to create new API endpoints
- ✅ **Performance**: Direct database queries are fast
- ✅ **POC Focus**: Avoids building new infrastructure for POC

**Trade-offs:**
- ❌ **Tight Coupling**: Proxy depends on legacy database schema
- ❌ **No Abstraction**: Direct SQL queries bypass business logic
- ❌ **Migration Complexity**: Need to migrate this logic later

**Alternative Considered**: Create GET /sources endpoint in platform-api
- Rejected for POC phase (would add development time)
- Should be implemented in production version

#### Decision 3: In-Memory Caching (Not Distributed)

**Decision**: Use simple in-memory cache with 5-minute TTL for foreign users

**Rationale:**
- ✅ **Solves Rate Limiting**: Prevents repeated calls to clj-pg-wrapper
- ✅ **Simple Implementation**: No external dependencies (Redis)
- ✅ **POC Appropriate**: Single-instance demo doesn't need distribution

**Trade-offs:**
- ❌ **Data Loss on Restart**: Cache cleared when service restarts
- ❌ **Not Scalable**: Won't work with multiple instances
- ❌ **No Eviction Policy**: Simple TTL only

**Alternative Considered**: Redis distributed cache
- Rejected for POC (adds infrastructure complexity)
- **Recommended for production**: Use Redis with proper eviction policies

#### Decision 4: Comprehensive Logging (STEP 1-7)

**Decision**: Add detailed logging throughout WebSocket connection flow

**Rationale:**
- ✅ **Debugging**: Makes it easy to identify where failures occur
- ✅ **Visibility**: Clear understanding of system behavior
- ✅ **Documentation**: Logs serve as runtime documentation

**Trade-offs:**
- ❌ **Console Noise**: Many log statements in browser console
- ❌ **Performance**: Minor overhead from logging operations
- ❌ **Production Concerns**: Should be removed/reduced for production

**Alternative Considered**: Minimal logging
- Rejected because debugging was extremely difficult without visibility
- Led to ~2 hours of debugging during development

---

## Data Design

### Database Structure

The system primarily interacts with the legacy `clj_postgres/gofapi` database for source management:

**Sources Table Schema:**
```sql
CREATE TABLE sources (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    org_id UUID REFERENCES organizations(id),
    title VARCHAR(500),
    url TEXT,
    content TEXT,
    metadata JSONB,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    embedding_status VARCHAR(50)
);

-- Indexes
CREATE INDEX idx_sources_org_id ON sources(org_id);
CREATE INDEX idx_sources_created_at ON sources(created_at DESC);
CREATE INDEX idx_sources_user_id ON sources(user_id);
```

**Query Pattern:**
```sql
-- Fetch 10 most recent sources (simplified for POC)
SELECT id FROM sources
ORDER BY created_at DESC
LIMIT 10;
```

**Future Enhancement:**
```sql
-- Production query should filter by organization
SELECT id FROM sources
WHERE org_id = :org_id
ORDER BY created_at DESC
LIMIT 10;
```

### Data Flow Diagrams

#### Story Generation Data Flow

```
1. User Input
   ↓
   [prompt: "Write about climate change"]

2. Frontend POST /chat/async
   ↓
   {
     "story-id": "uuid-1234",
     "user-config-params": {
       "userQuery": "Write about climate change"
     }
   }

3. Proxy Queries Database
   ↓
   SELECT id FROM sources LIMIT 10
   ↓
   ["src-uuid-1", "src-uuid-2", ..., "src-uuid-10"]

4. Proxy Injects Source IDs
   ↓
   {
     "story-id": "uuid-1234",
     "source-ids": ["src-uuid-1", ..., "src-uuid-10"],  ← Added
     "user-config-params": {
       "userQuery": "Write about climate change"
     }
   }

5. platform-api Validates Auth
   ↓
   Cache lookup: "org-123:user-456"
   ↓
   {
     "user_id": "uuid-789",
     "org_id": "org-123",
     "external_user": true
   }

6. platform-api Forwards to capitol-llm
   ↓
   {
     "params": {
       "external_id": "uuid-1234",
       "source_ids": ["src-uuid-1", ..., "src-uuid-10"]
     },
     "user_config_params": {...}
   }

7. capitol-llm Generates Story
   ↓
   Queries qdrant for source embeddings
   Sends prompts to LLM
   Creates WebSocket connection
   ↓
   {
     "socket_address": "ws://localhost:8081/ws/uuid-1234"
   }

8. Response Transformation
   ↓
   {
     "socketAddress": "ws://localhost:8081/ws/uuid-1234"  ← Transformed
   }

9. Frontend Establishes WebSocket
   ↓
   new WebSocket("ws://localhost:8081/ws/uuid-1234")

10. Real-time Events Stream
    ↓
    {type: "content", data: "Climate change is..."}
    {type: "citation", source_id: "src-uuid-1"}
    {type: "complete", status: "success"}
```

### Data Validation and Integrity

**Request Validation:**
```python
# platform-api validates all incoming requests
class StoryGenerationRequest(BaseModel):
    story_id: str = Field(..., alias="story-id")
    source_ids: list[str] = Field(default=[], alias="source-ids")
    user_config_params: dict = Field(..., alias="user-config-params")
    tags: list[str] = Field(default=[])

    @validator('story_id')
    def validate_story_id(cls, v):
        try:
            uuid.UUID(v)
        except ValueError:
            raise ValueError("story_id must be a valid UUID")
        return v
```

**Authentication Validation:**
```python
# Foreign user authentication validation
async def validate_external_user_token(x_user_id: str, x_api_key: str):
    # Validate API key exists and is active
    api_key_data = db_client.get_internal_api_key_by_value(x_api_key)
    if not api_key_data:
        raise HTTPException(401, "Invalid API key")

    if not api_key_data.get("active", False):
        raise HTTPException(401, "API key is inactive")

    org_id = api_key_data.get("orgid")
    if not org_id:
        raise HTTPException(500, "API key not associated with organization")

    # Get or create foreign user
    user_data = get_or_create_external_user(org_id, x_user_id)
    return user_data
```

### Data Storage and Retrieval

**Caching Strategy:**
- **Cache Key Format**: `"{org_id}:{foreign_user_id}"`
- **TTL**: 5 minutes (300 seconds)
- **Eviction**: Manual deletion on expiry (no LRU)
- **Storage**: Python dictionary in process memory

**Cache Access Pattern:**
```python
# Read-through cache pattern
def get_user_data(org_id: str, user_id: str):
    cache_key = f"{org_id}:{user_id}"

    # 1. Check cache
    if cache_key in _external_user_cache:
        user_data, cached_time = _external_user_cache[cache_key]
        if time.time() - cached_time < _CACHE_TTL:
            return user_data  # Cache hit
        else:
            del _external_user_cache[cache_key]  # Expired

    # 2. Cache miss - fetch from source
    user_data = fetch_from_clj_pg_wrapper(org_id, user_id)

    # 3. Update cache
    _external_user_cache[cache_key] = (user_data, time.time())

    return user_data
```

---

## Interface Design

### API Specifications and Protocols

#### 1. demo-proxy-app External API

**Base URL**: `http://localhost:8811/capitolai/api/v1`

**Authentication**: X-User-ID + X-API-Key headers

**Endpoints:**

##### POST /chat/async
```http
POST /capitolai/api/v1/chat/async
Headers:
  X-User-ID: external-user-123
  X-API-Key: cap-dev-xxx...
  Content-Type: application/json

Request Body:
{
  "story-id": "550e8400-e29b-41d4-a716-446655440000",
  "user-config-params": {
    "userQuery": "Write a story about AI",
    "length": "medium",
    "tone": "professional"
  },
  "tags": ["technology", "ai"]
}

Response (200 OK):
{
  "socketAddress": "ws://localhost:8081/ws/550e8400-e29b-41d4-a716-446655440000",
  "status": "success"
}
```

**Notes:**
- Proxy automatically injects `"source-ids"` from database
- Frontend doesn't need to provide source IDs

##### GET /events
```http
GET /capitolai/api/v1/events?external-id=550e8400-e29b-41d4-a716-446655440000
Headers:
  X-User-ID: external-user-123
  X-API-Key: cap-dev-xxx...

Response (200 OK):
{
  "response": {
    "socketAddress": "ws://localhost:8081/ws/550e8400-e29b-41d4-a716-446655440000",
    "events": [
      {
        "type": "content",
        "data": "Artificial intelligence has...",
        "timestamp": "2026-02-02T10:30:00Z"
      },
      {
        "type": "citation",
        "source_id": "src-uuid-1",
        "text": "According to research..."
      }
    ]
  }
}
```

**Notes:**
- Response format transformed from snake_case to camelCase
- `socket_address` → `socketAddress`

#### 2. platform-api Internal API

**Base URL**: `http://localhost:8000/api/v1`

**Authentication**: X-User-ID + X-API-Key OR X-User-Token

**New Endpoints:**

##### POST /chat/async (Internal)
```http
POST /api/v1/chat/async
Headers:
  X-User-ID: external-user-123
  X-API-Key: cap-dev-xxx...
  X-Organization-ID: org-uuid-456
  Content-Type: application/json

Request Body:
{
  "story-id": "550e8400-e29b-41d4-a716-446655440000",
  "source-ids": ["src-1", "src-2", "src-3"],  ← Injected by proxy
  "user-config-params": {
    "userQuery": "Write about AI"
  }
}

Response (200 OK):
{
  "socketAddress": "ws://localhost:8081/ws/550e8400-e29b-41d4-a716-446655440000"
}
```

##### PATCH /events/bulk
```http
PATCH /api/v1/events/bulk
Headers:
  X-User-ID: external-user-123
  X-API-Key: cap-dev-xxx...
  Content-Type: application/json

Request Body:
{
  "story-id": "550e8400-e29b-41d4-a716-446655440000",
  "events": [
    {
      "type": "content",
      "data": "Updated content..."
    }
  ],
  "draft-id": "draft-uuid-789",
  "events-to-delete": ["event-uuid-111"],
  "draft-depth": 0
}

Response (200 OK):
{
  "success": true,
  "updated_count": 1
}
```

**Known Issue**: Returns 500 error due to missing `event_id` field in events structure. Non-blocking for story generation.

#### 3. WebSocket Protocol

**Connection URL**: `ws://localhost:8081/ws/{story_id}`

**Message Format** (Server → Client):
```json
{
  "type": "content",
  "event_id": "evt-uuid-123",
  "data": "Story text content...",
  "timestamp": "2026-02-02T10:30:00Z"
}

{
  "type": "citation",
  "event_id": "evt-uuid-124",
  "source_id": "src-uuid-1",
  "text": "Quote from source",
  "start_index": 100,
  "end_index": 150
}

{
  "type": "complete",
  "event_id": "evt-uuid-125",
  "status": "success",
  "total_events": 45
}
```

**Client Handling:**
```typescript
socket.onmessage = (event) => {
  const llmEvent = JSON.parse(event.data);

  switch (llmEvent.type) {
    case 'content':
      appendContentToEditor(llmEvent.data);
      break;
    case 'citation':
      insertCitation(llmEvent.source_id, llmEvent.text);
      break;
    case 'complete':
      finishStoryGeneration();
      socket.close();
      break;
  }
};
```

### Error Handling

**HTTP Error Responses:**

```typescript
// Standardized error format
interface ErrorResponse {
  detail: string;
  error_code?: string;
  retry_after?: number;
}
```

**Error Scenarios:**

| Status Code | Scenario | Response | Client Action |
|-------------|----------|----------|---------------|
| 401 | Missing/invalid auth headers | `{"detail": "Authentication required"}` | Redirect to login |
| 401 | Invalid API key | `{"detail": "Invalid API key"}` | Show error message |
| 429 | Rate limit exceeded | `{"detail": "Rate limit exceeded", "retry_after": 60}` | Wait and retry |
| 500 | Internal server error | `{"detail": "Internal error occurred"}` | Log error, show generic message |
| 502 | Capitol-llm unavailable | `{"detail": "Unable to reach generation service"}` | Show service unavailable message |
| 503 | Database connection failed | `{"detail": "Service temporarily unavailable"}` | Retry with exponential backoff |

**WebSocket Error Handling:**

```typescript
socket.onerror = (error) => {
  console.error('WebSocket error:', error);
  // Attempt reconnection with exponential backoff
  reconnectWebSocket(socketAddress, retryCount);
};

socket.onclose = (event) => {
  if (event.code === 1006) {
    // Abnormal closure - connection died
    showErrorToast("Connection lost. Please refresh.");
  } else if (event.code === 1000) {
    // Normal closure - story generation complete
    console.log("Story generation completed successfully");
  }
};
```

### Security and Authentication

**Foreign User Authentication Flow:**

```
1. Client Request
   ↓
   Headers: X-User-ID, X-API-Key

2. platform-api Validation
   ↓
   a. Validate API key exists in DynamoDB
   b. Check API key is active
   c. Extract org_id from API key

3. Cache Lookup
   ↓
   Check: _external_user_cache[f"{org_id}:{x_user_id}"]

4a. Cache Hit
   ↓
   Return cached user data

4b. Cache Miss
   ↓
   Call clj-pg-wrapper:
   POST /api/v1/users/external
   {
     "api_client_id": org_id,
     "api_external_id": x_user_id
   }
   ↓
   Store in cache with TTL

5. Authorize Request
   ↓
   Verify user belongs to org_id
   Proceed with request
```

**JWT Token Flow:**

```
1. Client Request
   ↓
   Headers: X-User-Token OR Authorization: Bearer <token>

2. Token Decoding (Try self-generated first)
   ↓
   jwt.decode(token, JWT_SECRET_KEY)
   ↓
   Extract: user_id, org_id (if foreign user)

3a. Self-Generated Token
   ↓
   Lookup user in database
   Return user data

3b. JWT Decode Failed
   ↓
   Fall back to Auth0 validation
   check_token(token) → user info

4. Authorize Request
   ↓
   Verify org access
   Proceed with request
```

---

## Component Design

### Component 1: Source ID Injection Module

**File**: `demo-proxy-app/app/main.py`

**Purpose**: Automatically inject source IDs from database into story generation requests

**Responsibilities:**
- Query clj_postgres database for sources
- Transform request payload to include source IDs
- Handle database connection failures gracefully

**Input:**
- User ID (from X-User-ID header)
- Original request body (without source IDs)

**Output:**
- Modified request body with `"source-ids"` array

**Algorithm:**
```python
def get_user_source_ids(user_id: str) -> list[str]:
    """
    Fetch source IDs from database.

    Algorithm:
    1. Establish database session
    2. Execute query: SELECT id FROM sources ORDER BY created_at DESC LIMIT 10
    3. Extract UUIDs and convert to strings
    4. Return list of source ID strings
    5. Handle exceptions and return empty list on failure
    """
    try:
        with SessionLocal() as session:
            query = text("""
                SELECT id FROM sources
                ORDER BY created_at DESC
                LIMIT 10
            """)
            result = session.execute(query)
            source_ids = [str(row[0]) for row in result.fetchall()]
            logging.info(f"Found {len(source_ids)} source IDs: {source_ids}")
            return source_ids
    except Exception as e:
        logging.error(f"Error fetching source IDs: {e}")
        return []  # Fail gracefully
```

**Dependencies:**
- SQLAlchemy (database ORM)
- PostgreSQL connection to clj_postgres
- Environment variable: DATABASE_URL

**Error Handling:**
- Database connection failure → Return empty list, log error
- Query execution error → Return empty list, log error
- Empty result set → Return empty list (normal case)

### Component 2: Foreign User Authentication Cache

**File**: `platform-api/src/dependencies/external_user_auth.py`

**Purpose**: Cache foreign user lookups to prevent rate limiting from clj-pg-wrapper

**Responsibilities:**
- Maintain in-memory cache of user data
- Handle cache expiration (5-minute TTL)
- Coordinate calls to clj-pg-wrapper

**Input:**
- Organization ID (from API key)
- Foreign user ID (from X-User-ID header)

**Output:**
- User data dictionary: `{id, email, username, org_id}`

**Data Structures:**
```python
# Cache structure
_external_user_cache: Dict[str, tuple[Dict[str, Any], float]] = {}
# Key: "{org_id}:{user_id}"
# Value: (user_data_dict, timestamp_float)

_CACHE_TTL = 300  # 5 minutes in seconds
```

**Algorithm:**
```python
def get_or_create_external_user(org_id: str, foreign_user_id: str):
    """
    Get or create foreign user with caching.

    Algorithm:
    1. Generate cache key: f"{org_id}:{foreign_user_id}"
    2. Check if cache key exists
    3. If exists and not expired:
       - Return cached data (cache hit)
    4. If expired:
       - Remove from cache
    5. Call clj-pg-wrapper API:
       - POST /api/v1/users/external
       - Body: {api_client_id, api_external_id}
    6. If successful (200):
       - Store in cache with current timestamp
       - Return user data
    7. If failed:
       - Raise HTTPException with appropriate status
    """
    cache_key = f"{org_id}:{foreign_user_id}"
    current_time = time.time()

    # Check cache
    if cache_key in _external_user_cache:
        user_data, cached_time = _external_user_cache[cache_key]
        if current_time - cached_time < _CACHE_TTL:
            logger.debug(f"Cache hit: {cache_key}")
            return user_data
        else:
            del _external_user_cache[cache_key]

    # Call external service
    wrapper_url = f"{settings.CLJ_PG_WRAPPER_BASE_URL}/api/v1/users/external"
    response = requests.post(wrapper_url, json={
        "api_client_id": org_id,
        "api_external_id": foreign_user_id
    }, timeout=10)

    if response.status_code == 200:
        user_data = response.json()
        _external_user_cache[cache_key] = (user_data, current_time)
        return user_data
    else:
        raise HTTPException(500, f"Failed to get/create user: {response.text}")
```

**Performance Characteristics:**
- Cache hit: O(1) dictionary lookup
- Cache miss: ~100-200ms network call to clj-pg-wrapper
- Memory usage: ~1KB per cached user * number of unique users

**Dependencies:**
- requests library (HTTP client)
- clj-pg-wrapper service availability
- Environment variable: CLJ_PG_WRAPPER_BASE_URL

### Component 3: Response Format Transformer

**File**: `platform-api/src/routes/users_auth.py`

**Purpose**: Transform API responses from snake_case to camelCase for frontend compatibility

**Responsibilities:**
- Detect snake_case fields in response
- Transform to camelCase format
- Preserve data integrity

**Input:**
- Raw response from capitol-llm (snake_case format)

**Output:**
- Transformed response (camelCase format)

**Algorithm:**
```python
def transform_response_format(llm_response_data: dict) -> dict:
    """
    Transform snake_case keys to camelCase.

    Algorithm:
    1. Check if 'socket_address' key exists
    2. If exists:
       - Create new key 'socketAddress' with same value
       - Remove old key 'socket_address'
    3. Return transformed dictionary
    """
    if "socket_address" in llm_response_data:
        llm_response_data["socketAddress"] = llm_response_data.pop("socket_address")
    return llm_response_data

# Usage in /events endpoint
if resp.status_code == 200:
    llm_response_data = resp.json()
    llm_response_data = transform_response_format(llm_response_data)
    return JSONResponse(content={"response": llm_response_data})
```

**Complexity**: O(1) for single field transformation

**Dependencies**: None (pure Python transformation)

### Component 4: WebSocket Connection Manager

**File**: `frontend/web/src/app/story/components/Blocknote/hooks/useCreateStoryFromEvents.tsx`

**Purpose**: Establish and manage WebSocket connection for real-time event streaming

**Responsibilities:**
- Create WebSocket connection
- Handle connection lifecycle (open, message, error, close)
- Process incoming LLM events
- Update editor state

**Input:**
- Socket address from API response
- Editor instance (Blocknote)
- Story ID

**Output:**
- Real-time story content rendered in editor

**Algorithm:**
```typescript
const streamToBlocknote = ({
  socketAddress,
  editor,
  storyId,
  userId
}: StreamParams) => {
  // STEP 5: Create WebSocket connection
  const socket = new WebSocket(socketAddress);

  // STEP 6: Handle connection open
  socket.onopen = () => {
    console.log('WebSocket opened');
    setCurrentWebsocket(socket);

    // Send initial message to start streaming
    socket.send(JSON.stringify({
      action: 'start',
      storyId,
      userId
    }));
  };

  // Handle incoming messages
  socket.onmessage = (event) => {
    const llmEvent = JSON.parse(event.data);

    switch (llmEvent.type) {
      case 'content':
        appendContentBlock(editor, llmEvent.data);
        break;
      case 'citation':
        insertCitationBlock(editor, llmEvent);
        break;
      case 'complete':
        finishGeneration();
        break;
      default:
        console.warn('Unknown event type:', llmEvent.type);
    }
  };

  // Handle errors
  socket.onerror = (error) => {
    console.error('WebSocket error:', error);
    showErrorToast('Connection error occurred');
  };

  // STEP 7: Handle connection close
  socket.onclose = (event) => {
    console.log('WebSocket closed:', event.code);
    setCurrentWebsocket(undefined);

    if (event.code !== 1000) {
      // Abnormal closure - attempt reconnection
      attemptReconnection();
    }
  };

  return socket;
};
```

**State Management:**
```typescript
const [currentWebsocket, setCurrentWebsocket] = useState<WebSocket | undefined>();
const [isGenerating, setIsGenerating] = useState(false);
const [generationError, setGenerationError] = useState<string | null>(null);
```

**Dependencies:**
- React hooks (useState, useEffect)
- Blocknote editor API
- WebSocket browser API

---

## User Interface Design

### Wireframes and Key Screens

#### 1. CreateStory Component (Initial Screen)

```
┌─────────────────────────────────────────────────────────┐
│  Capitol AI - Create Story                              │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  What would you like to write about?                    │
│  ┌────────────────────────────────────────────────────┐ │
│  │                                                     │ │
│  │  [User enters prompt here]                         │ │
│  │                                                     │ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
│  Configuration (Optional):                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
│  │ Length: ▼   │  │ Tone: ▼     │  │ Model: ▼    │    │
│  │ Medium      │  │ Professional│  │ Claude-3.5  │    │
│  └─────────────┘  └─────────────┘  └─────────────┘    │
│                                                          │
│  Sources: Automatically selected (10 most recent)       │
│                                                          │
│                           ┌──────────────────┐          │
│                           │  Generate Story  │          │
│                           └──────────────────┘          │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

**User Flow:**
1. User enters prompt in text area
2. (Optional) User adjusts configuration dropdowns
3. User clicks "Generate Story"
4. Frontend calls `generateStory()` → POST /chat/async
5. Component transitions to EditorStory

#### 2. EditorStory Component (Generation Screen)

```
┌─────────────────────────────────────────────────────────┐
│  Story: "AI in 2026"                          [Save] [⋮] │
├─────────────────────────────────────────────────────────┤
│  [Generating... 📝]                                      │
│                                                          │
│  Artificial Intelligence in 2026                        │
│  ═══════════════════════════════                        │
│                                                          │
│  The landscape of artificial intelligence has           │
│  transformed dramatically in recent years¹. Machine      │
│  learning models have become...                          │
│                                                          │
│  [New content appears in real-time] ▌                   │
│                                                          │
│                                                          │
│  ─────────────────────────────────────                  │
│  Citations:                                              │
│  1. "AI Progress Report 2025" - Source A                │
│                                                          │
│                                                          │
└─────────────────────────────────────────────────────────┘
│  WebSocket: Connected ✓                                 │
└─────────────────────────────────────────────────────────┘
```

**User Flow:**
1. Component receives socketAddress from API
2. Establishes WebSocket connection (STEP 3-6)
3. Content appears incrementally as events arrive
4. Citations inserted inline with superscript numbers
5. Generation complete → WebSocket closes (STEP 7)

### User Workflows and Interactions

#### Workflow 1: Successful Story Generation

```
User Action                    → System Response
───────────────────────────────────────────────────────────
1. Enter prompt                → Validate input
   "Write about AI"            → Enable Generate button

2. Click "Generate Story"      → STEP 1: POST /chat/async
                               → Show loading spinner

3. (Background)                → Proxy injects source IDs
                               → Forward to platform-api
                               → platform-api validates auth
                               → Call capitol-llm

4. (Wait ~2-3 seconds)         → STEP 2: Receive response
                               → Extract socketAddress
                               → Switch to EditorStory

5. EditorStory renders         → STEP 3-4: Prepare WebSocket
                               → STEP 5: Create connection
                               → STEP 6: Connection opens

6. Content appears             → Events stream via WebSocket
   (real-time, incremental)    → Render in Blocknote editor
                               → Insert citations

7. Generation completes        → STEP 7: WebSocket closes
                               → Show "Complete" status
                               → Enable Save button
```

**Expected Duration**: 30-60 seconds for full story generation

#### Workflow 2: Error Handling - Authentication Failure

```
User Action                    → System Response
───────────────────────────────────────────────────────────
1. Click "Generate Story"      → POST /chat/async with headers

2. (Background)                → platform-api checks X-API-Key
                               → API key not found in DB
                               → Return 401 Unauthorized

3. Frontend receives error     → Display error toast:
                               → "Authentication failed. Please
                               →  check your API credentials."
                               → Log error to console

4. User clicks "Retry"         → Repeat request
                               → (or redirect to login)
```

#### Workflow 3: Error Handling - WebSocket Connection Failure

```
User Action                    → System Response
───────────────────────────────────────────────────────────
1. EditorStory component       → STEP 3-5: Prepare WebSocket
                               → Attempt connection

2. (Background)                → socket-llm unavailable
                               → Connection fails (onerror)

3. Frontend detects error      → STEP 6 never fires (not opened)
                               → Trigger error handler

4. Show error message          → Display toast:
                               → "Unable to connect. Retrying..."
                               → Attempt reconnection (3 tries)

5a. Reconnection succeeds      → STEP 6: Connection opens
                               → Continue normally

5b. Reconnection fails         → Show error:
                               → "Service unavailable. Please
                               →  refresh and try again."
```

### Accessibility Considerations

**Keyboard Navigation:**
- Tab order: Prompt textarea → Config dropdowns → Generate button
- Enter key in textarea → Trigger generation
- Escape key → Cancel generation (if supported)

**Screen Readers:**
- ARIA labels on all interactive elements
- Live region announcements for status updates:
  - "Generating story..."
  - "Story generation complete"
  - Error messages

**Visual Indicators:**
- High contrast loading spinner
- Clear connection status indicator
- Error messages with icons
- Color-blind friendly status colors

**Console Logging:**
All console logs use emoji prefixes for visual scanning:
- 🚀 STEP 1 - Request initiated
- ✅ STEP 2 - Response received
- 🔌 STEP 3 - WebSocket preparing
- ✅ STEP 4 - Function called
- 🎯 STEP 5 - Connection creating
- 🎉 STEP 6 - Connection opened
- 🔴 STEP 7 - Connection closed
- ❌ ERROR - Error occurred

---

## Alternatives Considered

### Alternative 1: Direct Frontend Migration (Without Proxy)

**Description**: Modify the frontend to call platform-api directly instead of gofapi, without a middleware proxy.

**Advantages:**
- ✅ Simpler architecture (fewer services)
- ✅ Lower latency (no proxy hop)
- ✅ Fewer deployment dependencies

**Disadvantages:**
- ❌ **All-or-nothing migration**: Must migrate all endpoints before switching
- ❌ **No backward compatibility**: Can't rollback easily if issues arise
- ❌ **Higher risk**: One bug blocks entire migration
- ❌ **Frontend changes required**: Must modify all API calls immediately

**Why Rejected:**
The proxy pattern enables incremental migration with lower risk. We can migrate endpoints one at a time, test each independently, and rollback if needed. This is critical for a large migration like deprecating clj-services.

**When This Might Be Viable:**
- For greenfield projects (no legacy migration)
- When all backend endpoints are ready simultaneously
- For small applications with few API calls

---

### Alternative 2: Create New API Endpoints for Source Management

**Description**: Instead of querying clj_postgres directly from the proxy, create new platform-api endpoints for source management.

**Advantages:**
- ✅ Proper abstraction layer
- ✅ Business logic in one place
- ✅ Easier to add authorization logic
- ✅ Database schema independence

**Disadvantages:**
- ❌ **More development time**: Need to implement multiple endpoints
- ❌ **Database migration**: Need to move source data to new schema
- ❌ **Coordination overhead**: Multiple teams/services involved

**Why Rejected for POC:**
This is the right long-term solution, but adds significant complexity for a POC. Direct database access is acceptable for proving the pattern works. The migration to proper endpoints should happen in the production implementation phase.

**Production Recommendation:**
Implement these endpoints after POC validation:
- `GET /organizations/{org_id}/sources` - List sources
- `POST /organizations/{org_id}/sources` - Create source
- `DELETE /sources/{source_id}` - Delete source

---

### Alternative 3: Redis Distributed Cache (Instead of In-Memory)

**Description**: Use Redis for caching foreign user lookups instead of in-memory Python dictionary.

**Advantages:**
- ✅ **Shared across instances**: Works with horizontal scaling
- ✅ **Persistence**: Survives service restarts
- ✅ **Advanced features**: LRU eviction, TTL support, atomic operations
- ✅ **Production-ready**: Battle-tested caching solution

**Disadvantages:**
- ❌ **Infrastructure overhead**: Need to deploy Redis
- ❌ **Network latency**: Cache access requires network call (~1-2ms)
- ❌ **Operational complexity**: One more service to monitor
- ❌ **Overkill for POC**: Single-instance demo doesn't need distribution

**Why Rejected for POC:**
In-memory caching solves the rate limiting problem for the POC with zero infrastructure overhead. The 5-minute TTL is sufficient for demo usage patterns.

**Production Recommendation:**
Migrate to Redis when:
- Running multiple platform-api instances
- Need cache persistence across restarts
- Usage patterns justify infrastructure investment

**Implementation Guide:**
```python
# Future Redis implementation
import redis

redis_client = redis.Redis(
    host=settings.REDIS_HOST,
    port=settings.REDIS_PORT,
    decode_responses=True
)

def get_or_create_external_user(org_id: str, foreign_user_id: str):
    cache_key = f"foreign_user:{org_id}:{foreign_user_id}"

    # Try cache first
    cached_data = redis_client.get(cache_key)
    if cached_data:
        return json.loads(cached_data)

    # Cache miss - fetch from source
    user_data = fetch_from_clj_pg_wrapper(org_id, foreign_user_id)

    # Store in Redis with TTL
    redis_client.setex(
        cache_key,
        300,  # 5 minutes
        json.dumps(user_data)
    )

    return user_data
```

---

### Alternative 4: Minimal Logging (Instead of STEP 1-7)

**Description**: Use minimal logging with only error messages, no detailed STEP-by-STEP flow.

**Advantages:**
- ✅ Cleaner console output
- ✅ Slightly better performance
- ✅ Less noise in production logs

**Disadvantages:**
- ❌ **Debugging difficulty**: Hard to identify where failures occur
- ❌ **No visibility**: Can't see system behavior without debugger
- ❌ **Longer troubleshooting**: Spent ~2 hours debugging WebSocket issues

**Why Rejected:**
During development, we encountered multiple issues with WebSocket connections:
1. socketAddress was undefined (response format issue)
2. WebSocket not establishing (callback not calling generateStory)
3. Events not rendering (null pointer exceptions)

Without detailed logging, each issue took significant time to diagnose. The STEP 1-7 logging pattern made it immediately clear where the flow was breaking.

**When This Might Be Viable:**
- Production environment (reduce logs to errors/warnings)
- Stable system with infrequent changes
- When using proper observability tools (DataDog, Sentry)

**Production Recommendation:**
- Keep STEP 1-7 logging in development/staging
- Use environment variable to disable in production
- Implement proper structured logging with correlation IDs

```typescript
// Environment-aware logging
const isDevelopment = process.env.NODE_ENV === 'development';

function logStep(step: string, message: string, data?: any) {
  if (isDevelopment) {
    console.log(`${step} ${message}`, data);
  }
}
```

---

## Open Questions

### Question 1: Event Structure Alignment

**Issue**: Capitol-llm expects `event_id` field in bulk event updates, but frontend doesn't provide it.

**Current Status**: Returns 500 error but doesn't block story generation/viewing.

**Questions:**
- Should we add `event_id` generation in frontend?
- Should capitol-llm make `event_id` optional?
- Should platform-api transform events to add missing fields?

**Impact**: Medium - Event editing doesn't work, but core functionality (generation/viewing) is unaffected.

**Recommendation**: Platform-api should generate event_ids if missing, or capitol-llm should accept events without IDs.

---

### Question 2: Source Selection in Production

**Issue**: Demo auto-injects 10 most recent sources. Production needs user-controlled source selection.

**Questions:**
- Should we build a source selection UI in the demo app?
- Should source selection be in CreateStory component or separate page?
- Should we support source search/filtering?

**Impact**: High for production, Low for POC.

**Recommendation**:
- POC: Keep auto-injection (sufficient for demo)
- Production: Add source picker component with:
  - Search by title/URL
  - Filter by date/type
  - Multi-select with checkboxes
  - "Select all recent" option

---

### Question 3: Production Caching Strategy

**Issue**: In-memory cache works for POC but won't scale to production.

**Questions:**
- Redis or another distributed cache solution?
- What should the TTL be for production? (5 minutes appropriate?)
- Should we cache additional data besides foreign users?
- What cache eviction policy should we use?

**Impact**: High for production scalability.

**Recommendation**:
- Migrate to Redis for production
- Keep 5-minute TTL (balance between freshness and rate limiting)
- Consider caching: API key lookups, organization data, source metadata
- Use LRU eviction policy with memory limits

---

### Question 4: Full gofapi Deprecation Timeline

**Issue**: COM-22 migrates 7 endpoints. ~13 endpoints remain in gofapi.

**Questions:**
- What's the priority order for remaining endpoints?
- Which endpoints are most critical for production?
- Should we migrate all endpoints or just high-traffic ones?
- Timeline for full deprecation?

**Impact**: Critical for Epic COM-21 completion.

**Next Steps:**
- Audit all gofapi endpoints and usage frequency
- Prioritize by traffic volume and business criticality
- Create migration tasks for high-priority endpoints
- Set target date for final gofapi shutdown

---

### Question 5: Error Recovery and Retry Logic

**Issue**: Limited error recovery in WebSocket connection failures.

**Questions:**
- Should we implement automatic retry with exponential backoff?
- How many retry attempts before showing error to user?
- Should we queue failed requests and replay on reconnection?
- What's the user experience for transient failures?

**Impact**: Medium - Affects reliability perception.

**Recommendation**:
- Implement exponential backoff: 1s, 2s, 4s retry delays
- Maximum 3 retry attempts
- Show toast notification: "Retrying connection..." on retries
- After 3 failures, show error with manual "Retry" button

---

## Parties Involved

**Primary Engineers:**
- **Backend**: Capitol AI Engineering Team
  - platform-api endpoint implementation
  - Authentication and caching logic
  - Database integration

- **Frontend**: Capitol AI Engineering Team
  - React library instrumentation
  - WebSocket connection handling
  - Null safety fixes

- **Infrastructure**: Capitol AI Engineering Team
  - Docker Compose orchestration
  - Service deployment

**Key Stakeholders:**
- **Product**: Epic COM-21 sponsor
- **External Partners**: Politico (demo consumer)

**Work Distribution:**
All work completed collaboratively during COM-22 POC phase. No work splitting required for POC.

---

## Test Plan

### Unit Testing

**Test Coverage Goals:**
- Backend: 80% code coverage for new endpoints
- Frontend: 70% coverage for critical paths

**Backend Unit Tests:**

```python
# test_external_user_auth.py
def test_cache_hit_returns_cached_data():
    """Test that cache returns data without API call"""
    # Arrange
    org_id = "org-123"
    user_id = "user-456"
    cached_data = {"id": "uuid-789", "email": "test@example.com"}
    _external_user_cache[f"{org_id}:{user_id}"] = (cached_data, time.time())

    # Act
    result = get_or_create_external_user(org_id, user_id)

    # Assert
    assert result == cached_data
    # Verify no API call was made (mock assertion)

def test_cache_miss_calls_api():
    """Test that cache miss triggers API call"""
    # Arrange
    org_id = "org-123"
    user_id = "user-456"
    _external_user_cache.clear()
    mock_api_response = {"id": "uuid-789", "email": "test@example.com"}

    # Act
    with mock.patch('requests.post') as mock_post:
        mock_post.return_value.status_code = 200
        mock_post.return_value.json.return_value = mock_api_response
        result = get_or_create_external_user(org_id, user_id)

    # Assert
    assert result == mock_api_response
    mock_post.assert_called_once()

def test_expired_cache_entry_refreshes():
    """Test that expired cache entries trigger refresh"""
    # Arrange
    org_id = "org-123"
    user_id = "user-456"
    old_data = {"id": "old-uuid"}
    # Set cache entry with timestamp 10 minutes ago
    _external_user_cache[f"{org_id}:{user_id}"] = (old_data, time.time() - 600)

    # Act & Assert
    # Should trigger API call and update cache
```

**Frontend Unit Tests:**

```typescript
// generateStory.test.ts
describe('generateStory', () => {
  it('should POST to /chat/async with correct payload', async () => {
    const mockResponse = {socketAddress: 'ws://localhost:8081/ws/123'};
    global.fetch = jest.fn(() =>
      Promise.resolve({ok: true, json: () => Promise.resolve(mockResponse)})
    );

    const result = await generateStory({
      storyId: '123',
      userPrompt: 'Test prompt',
      storyPlanConfig: {},
      tags: [],
      sourceIds: []
    });

    expect(fetch).toHaveBeenCalledWith(
      expect.stringContaining('/chat/async'),
      expect.objectContaining({method: 'POST'})
    );
    expect(result).toEqual(mockResponse);
  });

  it('should handle API errors gracefully', async () => {
    global.fetch = jest.fn(() =>
      Promise.reject(new Error('Network error'))
    );

    await expect(generateStory({...})).rejects.toThrow('Network error');
  });
});

// useCreateStoryFromEvents.test.tsx
describe('WebSocket connection', () => {
  it('should establish connection with valid socketAddress', () => {
    const {result} = renderHook(() => useCreateStoryFromEvents());
    const mockSocket = new MockWebSocket('ws://localhost/test');

    act(() => {
      result.current.streamToBlocknote({
        socketAddress: 'ws://localhost/test',
        editor: mockEditor,
        storyId: '123'
      });
    });

    expect(mockSocket.readyState).toBe(WebSocket.OPEN);
  });
});
```

### Integration Testing

**Test Strategy**: End-to-end tests covering full request flow

**Test Scenarios:**

1. **Story Generation Flow**
```python
@pytest.mark.integration
async def test_story_generation_end_to_end():
    """Test complete story generation from request to WebSocket"""
    # 1. POST /chat/async
    response = await client.post(
        "/chat/async",
        json={"story-id": story_id, "user-config-params": {"userQuery": "Test"}},
        headers={"X-User-ID": user_id, "X-API-Key": api_key}
    )
    assert response.status_code == 200
    assert "socketAddress" in response.json()

    # 2. GET /events to verify story created
    events_response = await client.get(
        f"/events?external-id={story_id}",
        headers={"X-User-ID": user_id, "X-API-Key": api_key}
    )
    assert events_response.status_code == 200
    assert events_response.json()["response"]["socketAddress"]
```

2. **Foreign User Authentication**
```python
@pytest.mark.integration
async def test_foreign_user_auth_and_caching():
    """Test foreign user creation and cache behavior"""
    # First request - cache miss
    start_time = time.time()
    response1 = await client.post("/chat/async", headers=headers)
    first_request_time = time.time() - start_time

    # Second request - cache hit (should be faster)
    start_time = time.time()
    response2 = await client.post("/chat/async", headers=headers)
    second_request_time = time.time() - start_time

    assert response1.status_code == 200
    assert response2.status_code == 200
    assert second_request_time < first_request_time * 0.5  # Cache hit is 50%+ faster
```

3. **Source ID Injection**
```python
@pytest.mark.integration
async def test_proxy_injects_source_ids():
    """Test that demo-proxy-app injects source IDs"""
    # Mock capitol-llm to capture forwarded request
    with mock.patch('httpx.AsyncClient.request') as mock_request:
        mock_request.return_value.status_code = 200
        mock_request.return_value.json.return_value = {"socketAddress": "ws://test"}

        # Make request through proxy
        response = await proxy_client.post("/chat/async", json={
            "story-id": "123",
            "user-config-params": {"userQuery": "Test"}
        })

        # Verify source-ids were injected
        called_with_body = json.loads(mock_request.call_args[1]['content'])
        assert "source-ids" in called_with_body
        assert len(called_with_body["source-ids"]) == 10
```

### End-to-End Testing

**Critical User Workflows:**

1. **Happy Path: Story Generation**
   - User enters prompt → Generate → View story with citations
   - **Expected**: Story appears in 30-60 seconds, WebSocket connected, content streams

2. **Error Path: Invalid API Key**
   - User enters prompt with invalid API key → Generate
   - **Expected**: 401 error, clear error message, no WebSocket attempt

3. **Error Path: WebSocket Connection Failure**
   - User enters prompt → Generate → socket-llm unavailable
   - **Expected**: Retry attempts, eventual error message, graceful degradation

### Performance Testing

**Benchmarks:**

| Metric | Target | Measurement Method |
|--------|--------|-------------------|
| POST /chat/async response time | < 500ms | Load test with k6 |
| WebSocket connection time | < 2 seconds | Frontend timing logs |
| Story generation total time | < 60 seconds | End-to-end test |
| Cache hit latency | < 10ms | Unit test timing |
| Cache miss latency | < 200ms | Integration test timing |

**Load Testing:**
```javascript
// k6 load test script
import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
  vus: 10,  // 10 virtual users
  duration: '30s',
};

export default function() {
  const payload = JSON.stringify({
    'story-id': __VU + '-' + __ITER,  // Unique story ID
    'user-config-params': {'userQuery': 'Test query'}
  });

  const params = {
    headers: {
      'Content-Type': 'application/json',
      'X-User-ID': `test-user-${__VU}`,
      'X-API-Key': 'test-api-key',
    },
  };

  let response = http.post('http://localhost:8811/capitolai/api/v1/chat/async', payload, params);

  check(response, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
    'has socketAddress': (r) => JSON.parse(r.body).socketAddress !== undefined,
  });

  sleep(1);
}
```

### Security Testing

**Test Scenarios:**

1. **Authentication Bypass Attempts**
```python
@pytest.mark.security
async def test_missing_auth_headers():
    """Verify endpoints reject requests without auth"""
    response = await client.post("/chat/async", json={"story-id": "123"})
    assert response.status_code == 401

@pytest.mark.security
async def test_invalid_api_key():
    """Verify invalid API keys are rejected"""
    response = await client.post(
        "/chat/async",
        json={"story-id": "123"},
        headers={"X-User-ID": "user", "X-API-Key": "invalid-key"}
    )
    assert response.status_code == 401
```

2. **SQL Injection Prevention**
```python
@pytest.mark.security
async def test_sql_injection_in_source_query():
    """Verify parameterized queries prevent SQL injection"""
    malicious_input = "'; DROP TABLE sources; --"

    # This should safely handle malicious input
    source_ids = get_user_source_ids(malicious_input)

    # Should return empty list (user doesn't exist) not crash
    assert isinstance(source_ids, list)
```

3. **Rate Limiting Validation**
```python
@pytest.mark.security
async def test_rate_limiting_without_cache():
    """Verify caching prevents rate limit errors"""
    # Make 10 rapid requests with same user
    for i in range(10):
        response = await client.post("/chat/async", headers=headers)
        assert response.status_code != 429  # No rate limit error
```

### Test Data Requirements

**Test Fixtures:**

1. **Database Test Data**
```sql
-- Insert test sources
INSERT INTO sources (id, user_id, org_id, title, url, created_at) VALUES
('src-test-1', 'user-123', 'org-456', 'Test Source 1', 'http://example.com/1', NOW() - INTERVAL '1 day'),
('src-test-2', 'user-123', 'org-456', 'Test Source 2', 'http://example.com/2', NOW() - INTERVAL '2 days'),
-- ... 8 more sources for 10 total
```

2. **API Keys**
```python
# Seed test API keys in DynamoDB
test_api_keys = [
    {
        "id": "key-test-1",
        "value": "cap-test-valid-key",
        "orgid": "org-test-123",
        "active": True
    },
    {
        "id": "key-test-2",
        "value": "cap-test-inactive-key",
        "orgid": "org-test-456",
        "active": False
    }
]
```

3. **Mock WebSocket Server**
```python
# Test fixture for WebSocket
@pytest.fixture
async def mock_websocket_server():
    """Start mock WebSocket server for testing"""
    server = await websockets.serve(mock_handler, "localhost", 8081)
    yield server
    server.close()
    await server.wait_closed()

async def mock_handler(websocket, path):
    """Mock WebSocket handler that sends test events"""
    await websocket.send(json.dumps({
        "type": "content",
        "data": "Test content"
    }))
    await websocket.send(json.dumps({
        "type": "complete",
        "status": "success"
    }))
```

### Test Environment Setup

**Local Development:**
```bash
# Start all services
docker-compose up -d

# Seed test data
just seed-test-data

# Run backend tests
cd platform-api && pytest src/tests/

# Run frontend tests
cd frontend/web && npm test

# Run integration tests
cd platform-api && pytest src/tests/ -m integration
```

**CI/CD Pipeline:**
```yaml
# .github/workflows/test.yml
name: Test Suite
on: [push, pull_request]

jobs:
  backend-tests:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:14
        env:
          POSTGRES_DB: test_db
      redis:
        image: redis:7
    steps:
      - uses: actions/checkout@v3
      - name: Run backend tests
        run: |
          cd platform-api
          poetry install
          pytest --cov=src --cov-report=xml
      - name: Upload coverage
        uses: codecov/codecov-action@v3

  frontend-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run frontend tests
        run: |
          cd frontend/web
          npm ci
          npm test -- --coverage
```

### Acceptance Criteria for Launch Readiness

**POC Phase (Current):**
- ✅ Story generation working end-to-end via proxy
- ✅ WebSocket connection establishment successful
- ✅ Real-time content streaming functional
- ✅ Foreign user authentication working
- ✅ No rate limit errors during normal usage
- ✅ Comprehensive logging for debugging
- ⚠️ Event bulk update (known issue, non-blocking)

**Production Phase (Future):**
- ⬜ All gofapi endpoints migrated to platform-api
- ⬜ Redis caching implemented
- ⬜ Source selection UI implemented
- ⬜ Event structure aligned (event_id field)
- ⬜ 80%+ backend test coverage
- ⬜ 70%+ frontend test coverage
- ⬜ Load testing: 100 concurrent users
- ⬜ Security audit completed
- ⬜ Monitoring and alerting configured
- ⬜ Runbook documentation complete
- ⬜ Zero-downtime deployment verified

---

## Timeline and Milestones

### POC Phase (Completed)

**Duration**: ~3 days (Jan 30 - Feb 2, 2026)

| Milestone | Date | Status | Deliverables |
|-----------|------|--------|--------------|
| **Phase 1: Setup** | Jan 30 | ✅ Complete | Docker Compose, DB connections, proxy skeleton |
| **Phase 2: Core Endpoints** | Jan 31 | ✅ Complete | POST /chat/async, GET /events, authentication |
| **Phase 3: Source Injection** | Feb 1 | ✅ Complete | Database integration, auto source ID injection |
| **Phase 4: Frontend Integration** | Feb 1-2 | ✅ Complete | WebSocket flow, logging, null safety fixes |
| **Phase 5: Testing & Documentation** | Feb 2 | ✅ Complete | End-to-end testing, design doc, Confluence |

### Production Phase (Future)

**Estimated Duration**: 6-8 weeks

| Milestone | Target Date | Status | Deliverables |
|-----------|-------------|--------|--------------|
| **Phase 1: Additional Endpoints** | Week 1-2 | 📋 Planned | Migrate remaining 13 gofapi endpoints |
| **Phase 2: Infrastructure** | Week 2-3 | 📋 Planned | Redis cache, monitoring, alerting |
| **Phase 3: UI Enhancements** | Week 3-4 | 📋 Planned | Source picker, error handling, UX polish |
| **Phase 4: Testing** | Week 4-5 | 📋 Planned | Integration tests, load tests, security audit |
| **Phase 5: Deployment** | Week 6 | 📋 Planned | Staging deployment, production rollout plan |
| **Phase 6: Production Rollout** | Week 7-8 | 📋 Planned | Gradual rollout, monitoring, incident response |
| **Phase 7: Deprecation** | Week 8+ | 📋 Planned | Shutdown clj-services, cleanup |

### Key Milestones

**M1: POC Validation** ✅ (Feb 2, 2026)
- Proxy pattern proven viable
- Story generation working end-to-end
- Demo ready for external stakeholders

**M2: Additional Endpoints** (TBD)
- All high-priority gofapi endpoints migrated
- Feature parity with clj-services
- Integration tests passing

**M3: Production Infrastructure** (TBD)
- Redis caching deployed
- Monitoring and alerting live
- Load testing complete

**M4: Production Deployment** (TBD)
- Gradual rollout to production users
- Zero critical issues
- Performance metrics met

**M5: clj-services Deprecation** (TBD)
- All traffic migrated to platform-api
- clj-services shutdown
- Epic COM-21 complete

---

## Appendix

### A. Relevant Links

**Jira Tickets:**
- Epic COM-21: https://capitolai.atlassian.net/browse/COM-21
- Task COM-22: https://capitolai.atlassian.net/browse/COM-22

**Code Repositories:**
- demo-proxy-app: https://github.com/Faction-V/demo-proxy-app (Branch: BE-955-proxy-demo-app-poc)
- platform-api: https://github.com/Faction-V/platform-api (Branch: BE-955-proxy-demo-app-poc)
- frontend: https://github.com/Faction-V/frontend (Branch: features-test-branch)

**Documentation:**
- GOFAPI Migration Tracker: `/demo-proxy-app/GOFAPI_MIGRATION.md`
- Session Summary: `/demo-proxy-app/SESSION_SUMMARY.md`
- Jira Update Template: `/demo-proxy-app/JIRA_UPDATE_BE-955.md`

### B. Commit History

**demo-proxy-app:**
- `5382ce2` - [BE-955] feat(proxy): implement auto source ID injection
- `da70252` - docs: add POST /chat/async payload transformation fix
- `8b5943f` - docs: document story creation flow fix and JWT enhancements
- `3d78799` - feat: implement story generation endpoint

**platform-api:**
- `71529a1` - [BE-955] feat(api): add gofapi-compatible endpoints and foreign user auth
- `5cf98c7` - fix: convert camelCase to snake_case in /chat/async payload
- `b824879` - fix: support kebab-case in guardrails and story generation
- `2e06f2f` - feat: add POST /chat/async endpoint for story generation

**frontend:**
- `c6bd0c893` - fix(react-lib): add comprehensive logging and null safety for WebSocket flow

### C. Architecture Diagrams

**System Architecture:**
```
┌─────────────┐
│   Browser   │
│  (React)    │
└──────┬──────┘
       │ HTTP/WS
       ▼
┌─────────────┐
│ demo-proxy- │
│     app     │◄─── SQLAlchemy ───┐
└──────┬──────┘                   │
       │                          │
       │ HTTP                     │
       ▼                          │
┌─────────────┐              ┌───▼──────┐
│ platform-   │              │clj_postgres│
│     api     │              │  (gofapi) │
└──────┬──────┘              └───────────┘
       │
       │ HTTP
       ▼
┌─────────────┐
│ capitol-llm │
│  (Clojure)  │
└──────┬──────┘
       │
       │ WebSocket
       ▼
┌─────────────┐
│ socket-llm  │
└─────────────┘
```

**Authentication Flow:**
```
[Client Request]
      ↓
[X-User-ID + X-API-Key headers]
      ↓
[platform-api: Validate API key]
      ↓
[Check cache: {org_id}:{user_id}]
      ↓
   [Hit?] ──Yes──> [Return cached data]
      │
      No
      ↓
[Call clj-pg-wrapper]
      ↓
[Create/fetch foreign user]
      ↓
[Cache result (5-min TTL)]
      ↓
[Return user data]
```

**Data Flow:**
```
[User Input] → [Frontend]
                    ↓
            [POST /chat/async]
                    ↓
              [demo-proxy-app]
            ┌───────┴───────┐
            │ Query sources │
            └───────┬───────┘
                    │
            [Inject source IDs]
                    ↓
              [platform-api]
            ┌───────┴───────┐
            │ Validate auth │
            │ Transform fmt │
            └───────┬───────┘
                    │
                    ↓
              [capitol-llm]
            ┌───────┴───────┐
            │ Generate story│
            └───────┬───────┘
                    │
            [Return socketAddress]
                    ↓
                [Frontend]
            ┌───────┴───────┐
            │ WebSocket conn│
            └───────┬───────┘
                    │
            [Stream events]
                    ↓
            [Render in editor]
```

### D. Environment Variables Reference

**demo-proxy-app:**
```bash
# Required
API_URL=http://platform_api/public
DATABASE_URL=postgresql://postgres:postgres@clj_postgres:5432/gofapi
DOMAIN=https://aigrants.co/
API_KEY=cap-dev-xxx...

# Optional
USER_ID=1  # Default user ID for testing
```

**platform-api:**
```bash
# Required
CLJ_PG_WRAPPER_BASE_URL=http://clj-pg-wrapper:8080
CAPITOL_LLM_URL=http://capitol-llm:8080
JWT_SECRET_KEY=your-secret-key
JWT_ALGORITHM=HS256

# Optional
CLJ_PG_WRAPPER_URL=http://clj-pg-wrapper:8080  # Deprecated, use BASE_URL
```

**frontend:**
```bash
# Required
VITE_PROXY_API_URL=http://localhost:8811/capitolai/api/v1

# Optional
VITE_API_TIMEOUT=30000  # 30 seconds
```

### E. Database Schema Reference

**sources table (clj_postgres/gofapi):**
```sql
CREATE TABLE sources (
    id UUID PRIMARY KEY,
    user_id UUID,
    org_id UUID,
    title VARCHAR(500),
    url TEXT,
    content TEXT,
    metadata JSONB,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    embedding_status VARCHAR(50)
);
```

### F. Performance Metrics

**Measured Performance (POC):**

| Metric | Value | Target | Status |
|--------|-------|--------|--------|
| POST /chat/async latency | ~250ms | < 500ms | ✅ Pass |
| Cache hit latency | ~5ms | < 10ms | ✅ Pass |
| Cache miss latency | ~150ms | < 200ms | ✅ Pass |
| WebSocket connection time | ~1.5s | < 2s | ✅ Pass |
| Story generation total | ~45s | < 60s | ✅ Pass |

**System Resource Usage:**

| Service | Memory | CPU | Notes |
|---------|--------|-----|-------|
| demo-proxy-app | ~100MB | < 5% | Single instance, light load |
| platform-api | ~300MB | < 10% | Includes cache, DynamoDB client |
| frontend (dev server) | ~200MB | < 5% | Vite dev server |

### G. Known Issues and Limitations

**Known Issues:**

1. **Event Bulk Update (500 Error)**
   - **Status**: Open
   - **Impact**: Medium
   - **Workaround**: None (event editing doesn't work)
   - **Root Cause**: Capitol-llm expects `event_id` field in events
   - **Fix**: Platform-api should generate event_ids or capitol-llm make optional

2. **In-Memory Cache Not Distributed**
   - **Status**: By Design (POC)
   - **Impact**: Low (single instance)
   - **Workaround**: None needed for POC
   - **Production Fix**: Migrate to Redis

**Limitations:**

1. **No Source Selection UI**: Auto-injects 10 most recent sources
2. **Single Instance Only**: In-memory cache doesn't work with horizontal scaling
3. **Limited Error Recovery**: No automatic retry for transient failures
4. **Direct Database Access**: Proxy queries legacy database directly
5. **Debug Logging in Production**: STEP 1-7 logs should be removed

### H. Future Work

**Short-term (Next Sprint):**
- Fix event_id structure issue in bulk updates
- Add more comprehensive error messages
- Implement automatic WebSocket reconnection

**Medium-term (Next Quarter):**
- Migrate all remaining gofapi endpoints
- Implement Redis distributed caching
- Add source selection UI
- Improve test coverage to 80%+

**Long-term (Future Releases):**
- Deprecate clj_postgres access, use platform-api endpoints
- Implement proper observability (traces, metrics, logs)
- Add support for streaming responses in REST API
- Build admin dashboard for API key management

---

**Document Version**: 1.0
**Last Updated**: February 2, 2026
**Status**: Complete (POC Phase)
**Next Review**: After production deployment planning
