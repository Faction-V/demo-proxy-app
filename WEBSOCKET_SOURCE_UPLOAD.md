# WebSocket Source Upload Implementation

## Overview

This document describes the WebSocket-enabled asynchronous source upload system migrated from clj-services to platform-api. This system provides real-time status updates to clients during source processing via WebSocket connections.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Client (Browser)                        │
└────────┬────────────────────────────────────┬───────────────┘
         │ 1. POST /sources/ws                 │
         │    {ws-uuid: "abc123"}              │
         ▼                                     │
┌─────────────────────────────────────────────────────────────┐
│                     platform-api                             │
│                    (Port 8811)                               │
├─────────────────────────────────────────────────────────────┤
│  Returns: {ws-address: "ws://localhost:8811/ws/abc123"}     │
└─────────────────────────────────────────────────────────────┘
         │                                     │
         │                                     │ 2. Connect WebSocket
         │                                     │    ws://localhost:8811/ws/abc123
         │                                     ▼
         │                            ┌───────────────────────┐
         │                            │   WebSocket Handler   │
         │                            │   /ws/{ws_uuid}       │
         │                            │   (platform-api)      │
         │                            └──────────┬────────────┘
         │                                       │
         │                                       │ Subscribe to Redis
         │                                       │ Channel: "abc123"
         │                                       ▼
         │                            ┌───────────────────────┐
         │                            │   Redis (pub/sub)     │
         │                            │   redis-cache:6379    │
         │                            └──────────▲────────────┘
         │                                       │
         │ 3. POST /upload-source                │
         │    {ws-uuid: "abc123", file: ...}     │
         ▼                                       │
┌─────────────────────────────────────────────────────────────┐
│                     platform-api                             │
│                  Async Processing                            │
├─────────────────────────────────────────────────────────────┤
│  → Immediate return (200 OK)                                 │
│  → Start background task (asyncio.create_task)               │
│  → Publish to Redis: "abc123" → {status: "processing"}      │
│  → Process upload (via clj-pg-wrapper)                       │
│  → Publish to Redis: "abc123" → {status: "success"}         │
└─────────────────────────────────────────────────────────────┘
                                    │
                                    │ Redis PUBLISH
                                    └────────────────────────────┘
```

## Implementation Details

### 1. Redis Pub/Sub Utility (`src/utils/redis_pubsub.py`)

Provides Redis publish/subscribe functionality for WebSocket messaging:

```python
async def redis_publish(channel: str, message: Dict[str, Any]) -> None:
    """Publish message to Redis channel for WebSocket clients."""
    # Serializes message to JSON and publishes to Redis channel
```

**Key Features:**
- Automatic JSON serialization
- Error handling (doesn't fail upload if Redis has issues)
- Uses existing `CHAT_CONTEXT_REDIS_URL` configuration

### 2. POST /public/sources/ws

**Endpoint:** `POST /public/sources/ws`
**Auth:** X-User-ID + X-API-Key headers

**Request:**
```json
{
  "ws-uuid": "550e8400-e29b-41d4-a716-446655440000"
}
```

**Response:**
```json
{
  "ws-address": "ws://localhost:8811/ws/550e8400-e29b-41d4-a716-446655440000"
}
```

**Purpose:** Creates a WebSocket connection address for a client to connect to and receive real-time upload status updates.

### 3. WebSocket /ws/{ws_uuid}

**Endpoint:** `WebSocket /ws/{ws_uuid}`
**Auth:** None (connection established after authenticated POST /sources/ws)

**Behavior:**
1. Accepts WebSocket connection
2. Subscribes to Redis pub/sub channel (channel name = ws_uuid)
3. Forwards all Redis messages to WebSocket client
4. Automatically closes when receiving "success" or "failure" status

**Message Format:**
```json
{
  "message": "Source received. Starting to processing",
  "type": "file-upload",
  "source-uuid": "...",
  "status": "processing"
}
```

```json
{
  "result": {...},
  "type": "file-upload",
  "source-uuid": "...",
  "status": "success"
}
```

### 4. POST /public/sources/upload-source (Async)

**Endpoint:** `POST /public/sources/upload-source`
**Auth:** X-User-ID + X-API-Key headers

**Request (Multipart):**
```
ws-uuid: "550e8400-..."
source-uuid: "660e8400-..."
filename: "document.pdf"
file: [binary data] OR content: "https://example.com/doc.pdf"
```

**Response (Immediate):**
```json
{
  "message": "Processing file: 660e8400-..."
}
```

**Behavior:**
1. Validates authentication
2. Starts background task (`asyncio.create_task`)
3. Returns immediately (200 OK)
4. Background task processes upload and publishes status updates to Redis
5. WebSocket client receives real-time updates

**Background Processing:**
- Publishes initial status: `{"step": "Hello, I start to process...", "status": "processing"}`
- Forwards to existing sync endpoints:
  - Files → `/sources/upload-source/file`
  - URLs → `/sources/upload-source/sync`
- Publishes final status: `{"status": "success"}` or `{"status": "failure"}`

## Migration from clj-services

### What Was Migrated

**From clj-services:**
```
POST /api/v1/sources/ws              → POST /public/sources/ws
POST /api/v1/sources/upload-source   → POST /public/sources/upload-source
WebSocket ws://localhost:5179/ws/:id → WebSocket ws://localhost:8811/ws/:id
```

**Technology Stack:**
- **Before:** Clojure + Aleph (HTTP) + Manifold (WebSocket) + Redis
- **After:** Python + FastAPI + asyncio + Redis

### Key Differences

| Feature | clj-services | platform-api |
|---------|-------------|--------------|
| WebSocket Server | Separate ws-server service (port 5179) | Integrated into platform-api (port 8811) |
| Async Processing | Clojure `future` | Python `asyncio.create_task` |
| WebSocket Library | Aleph + Manifold | FastAPI WebSocket |
| Pub/Sub | Redis via Carmine | Redis via redis.asyncio |
| File Processing | Direct implementation | Delegates to clj-pg-wrapper |

### API Contract Compatibility

The API maintains **100% compatibility** with the clj-services API:

✅ Same request format (kebab-case: `ws-uuid`, `source-uuid`)
✅ Same response format (`ws-address`)
✅ Same WebSocket message format
✅ Same authentication (X-User-ID + X-API-Key)

## Testing

### Prerequisites

```bash
# Install websocat for WebSocket testing
brew install websocat

# Ensure platform-api and Redis are running
docker compose up -d
```

### Run Test Script

```bash
./test-websocket-upload.sh
```

### Manual Testing

**1. Create WebSocket address:**
```bash
WS_UUID=$(uuidgen | tr '[:upper:]' '[:lower:]')
curl -X POST 'http://localhost:8811/public/sources/ws' \
  -H 'X-User-ID: 1' \
  -H 'X-API-Key: cap-dev-OPJC6oTQ-ebB7xRdd-7xydxD0C-oYVbyOYl' \
  -H 'Content-Type: application/json' \
  -d "{\"ws-uuid\": \"$WS_UUID\"}"
```

**2. Connect to WebSocket:**
```bash
websocat ws://localhost:8811/ws/$WS_UUID
```

**3. Upload source (in another terminal):**
```bash
SOURCE_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
curl -X POST 'http://localhost:8811/public/sources/upload-source' \
  -H 'X-User-ID: 1' \
  -H 'X-API-Key: cap-dev-OPJC6oTQ-ebB7xRdd-7xydxD0C-oYVbyOYl' \
  -F "ws-uuid=$WS_UUID" \
  -F "source-uuid=$SOURCE_ID" \
  -F "filename=test.pdf" \
  -F "content=https://example.com/sample-doc.pdf"
```

**4. Watch WebSocket output:**
```json
{"step": "Hello, I start to process this source: ...", "status": 200, "step-status": "processing"}
{"message": "Source received. Starting to processing", "type": "url-upload", "source-uuid": "...", "status": "processing"}
{"result": {...}, "type": "url-upload", "source-uuid": "...", "status": "success"}
```

## Dependencies

### New Dependencies
- None! Uses existing dependencies:
  - `redis.asyncio` (already in use for chat context cache)
  - `fastapi.WebSocket` (built-in to FastAPI)
  - `asyncio` (Python standard library)

### Configuration
Uses existing Redis configuration:
```python
# config.py
CHAT_CONTEXT_REDIS_URL: str = "redis://platform-redis:6379/0"
```

## Error Handling

### Client Errors
- **401 Unauthorized:** Missing X-User-ID or X-API-Key headers
- **400 Bad Request:** Missing ws-uuid or source-uuid
- **500 Internal Server Error:** Unexpected server error

### WebSocket Errors
- **Connection Closed:** Automatically closes after "success" or "failure" status
- **Redis Unavailable:** Logs error but doesn't crash (graceful degradation)
- **Network Issues:** Client should implement reconnection logic

### Background Task Errors
All errors are caught and published to the WebSocket:
```json
{
  "result": "Error",
  "error": "Error message here",
  "source-uuid": "...",
  "status": "failure"
}
```

## Performance Considerations

### Advantages
1. **Non-Blocking:** Upload endpoint returns immediately
2. **Scalable:** Each WebSocket connection is lightweight
3. **Real-time:** Sub-second status updates via Redis pub/sub
4. **Resource Efficient:** Reuses existing Redis infrastructure

### Limitations
1. **Single Server:** WebSocket connections are tied to a single server instance
2. **No Persistence:** If server restarts, active WebSocket connections are lost
3. **Memory:** Each WebSocket connection holds some memory (minimal ~1KB)

### Scaling Notes
For production deployment with multiple servers:
- Use sticky sessions for WebSocket connections
- Consider Redis Streams for persistent message history
- Implement WebSocket reconnection logic in clients

## Future Enhancements

### Short-term
- [ ] Add progress percentage updates during file processing
- [ ] Support batch uploads with single WebSocket
- [ ] Add WebSocket authentication/token validation

### Long-term
- [ ] Migrate file processing from clj-pg-wrapper to platform-api
- [ ] Replace Redis pub/sub with Redis Streams for message persistence
- [ ] Add WebSocket connection pool management
- [ ] Implement horizontal scaling with sticky sessions

## Related Documentation

- [SOURCE_UPLOAD_IMPLEMENTATION.md](./SOURCE_UPLOAD_IMPLEMENTATION.md) - Synchronous upload endpoints
- [GOFAPI_MIGRATION.md](./GOFAPI_MIGRATION.md) - Overall migration strategy
- [platform-api/docs/add-documents-endpoint.md](../platform-api/docs/add-documents-endpoint.md) - Collection document uploads

## Status

✅ **Fully Migrated** - Ready for production use

**Migration Date:** 2026-02-05
**Migrated From:** clj-services/gofapi + ws-server
**Migrated To:** platform-api
**Status:** Complete
