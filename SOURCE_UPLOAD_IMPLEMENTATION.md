# Source Document Upload and Embedding Implementation

## Session Date: 2026-02-02

## Overview

Implemented source document upload functionality with embedding generation to support story creation with custom documents in the demo proxy app. This fixes the story generation flow to properly utilize uploaded source documents.

## Problems Identified

### 1. Source IDs Not Passed to Capitol-LLM ❌

**Issue**: In `platform-api/src/routes/users_auth.py:1196`, source IDs were extracted from the request but **not passed** to capitol-llm during story generation.

```python
# BEFORE - source_ids extracted but unused
source_ids = body.get("source-ids") or body.get("source_ids", [])

llm_payload = {
    "params": {
        "external_id": external_id
        # source_ids missing here! ❌
    },
    ...
}
```

**Impact**: Stories couldn't use uploaded documents even if they were provided.

### 2. Missing Document Ingestion Endpoints ❌

The frontend needed endpoints to upload documents with embedding generation, but platform-api didn't have them. These endpoints exist in clj-services:

- `POST /api/v1/sources/upload-source/sync` - JSON/URL sources
- `POST /api/v1/sources/upload-source/file` - PDF/image files

## Changes Implemented

### 1. Fixed Source IDs Bug ✅

**File**: `platform-api/src/routes/users_auth.py:1234`

```python
# AFTER - source_ids now included
llm_payload = {
    "params": {
        "external_id": external_id,
        "source_ids": source_ids  # ✅ Now passed to capitol-llm
    },
    "user_config_params": transformed_user_config,
    "request_metadata": {
        "tags": tags
    }
}
```

**What this fixes**:
- Story generation can now retrieve and use uploaded source documents
- Source IDs flow through the complete pipeline: frontend → platform-api → capitol-llm

### 2. Implemented Upload Endpoints ✅

**File**: `platform-api/src/routes/users_auth.py` (lines 1310-1459)

Added two new endpoints that proxy to clj-services:

#### A. POST /public/sources/upload-source/sync

**Purpose**: Upload JSON data or URLs as sources with optional embedding generation

**Request**:
```bash
curl -X POST "http://localhost:8811/public/sources/upload-source/sync" \
  -H "Content-Type: application/json" \
  -H "X-User-ID: 1" \
  -H "X-API-Key: cap-dev-xxx" \
  -d '{
    "source-id": "uuid",
    "filename": "document.json",
    "generate-embedding": true,
    "tags": [{"Environment": "production"}],
    "data": {
      "title": "Climate Report",
      "content": "Climate change analysis...",
      "category": "Environment"
    }
  }'
```

**Response**:
```json
{
  "source-id": "uuid",
  "embedding-status": "COMPLETED"
}
```

**Flow**:
1. Validates X-User-ID + X-API-Key authentication
2. Forwards request to clj-services at `http://clojure-api:3333`
3. clj-services uploads JSON to S3
4. Creates source record in Postgres
5. If `generate-embedding: true`, calls Lambda to generate embeddings
6. Stores embeddings in Qdrant vector database
7. Returns source-id for use in story generation

#### B. POST /public/sources/upload-source/file

**Purpose**: Upload PDF or image files as sources

**Request**:
```bash
curl -X POST "http://localhost:8811/public/sources/upload-source/file" \
  -H "X-User-ID: 1" \
  -H "X-API-Key: cap-dev-xxx" \
  -F "source-id=uuid" \
  -F "filename=report.pdf" \
  -F "file=@/path/to/report.pdf"
```

**Response**:
```json
{
  "source-id": "uuid"
}
```

**Flow**:
1. Validates authentication
2. Parses multipart form data
3. Forwards to clj-services with aiohttp for async multipart upload
4. clj-services uploads file to S3 bucket `capitol-ai-user-documents`
5. Extracts text via OCR (for PDFs) or image processing
6. Creates source record in Postgres
7. Returns source-id

### 3. Created Test Script ✅

**File**: `demo-proxy-app/test-source-upload.sh`

Comprehensive test script that:

1. **Uploads JSON source** with embedding generation
2. **Waits for embedding** to complete (5 seconds)
3. **Generates story** with source-ids included
4. **Reports results** with detailed output

**Usage**:
```bash
cd /Users/johnkealy/srv/capitol/demo-proxy-app
./test-source-upload.sh
```

**What it tests**:
- ✅ Foreign user authentication (X-User-ID + X-API-Key)
- ✅ Source upload with embedding generation
- ✅ Story generation with source IDs
- ✅ Complete end-to-end flow

## Architecture

### Complete Story Generation Flow with Sources

```
┌──────────┐
│ Frontend │ (Port 5174)
└────┬─────┘
     │ 1. Upload source
     ▼
┌──────────────────┐
│  platform-api    │ (Port 8811)
│  /public/sources │
│  /upload-source  │
└────┬─────────────┘
     │ 2. Forward with auth
     ▼
┌──────────────┐
│ clj-services │ (Port 3333)
│   gofapi     │
└────┬─────────┘
     │ 3. Upload to S3
     │ 4. Store in Postgres
     │ 5. Generate embeddings
     ▼
┌──────────────┐
│   Lambda     │ → Qdrant (embeddings)
└──────────────┘

     │ 6. User requests story
     ▼
┌──────────────────┐
│  platform-api    │
│  /public/chat    │
│  /async          │
└────┬─────────────┘
     │ 7. Include source-ids ✅
     ▼
┌──────────────┐
│ capitol-llm  │ → Retrieves embeddings from Qdrant
└──────────────┘ → Generates story using sources
```

## Technical Details

### Authentication

All endpoints use **foreign user authentication**:
- **Headers**: `X-User-ID` and `X-API-Key`
- **Validation**: `validate_external_user_token()` in `dependencies/external_user_auth.py`
- **Returns**: `{id: user_uuid, org_id: organization_uuid}`

### Proxy Pattern

Both upload endpoints use a **proxy pattern** to clj-services:

**Why proxy instead of direct implementation?**
1. clj-services already has working upload logic
2. Integrates with existing S3 buckets and Lambda functions
3. Shares Postgres database with source records
4. Avoids duplicating complex embedding logic
5. Provides backward compatibility during migration

### Embedding Generation

**Process**:
1. Upload source to S3 bucket (per organization)
2. Call Lambda function: `invoke-generate-embeddings`
3. Lambda extracts text and generates vectors
4. Stores embeddings in Qdrant with metadata
5. Returns embedding hash and status

**Qdrant Integration**:
- Each organization has its own bucket in S3
- Embeddings stored with `org_id` for isolation
- Source documents retrievable via `source-id`

### Source ID Flow

**Frontend → platform-api → capitol-llm**:

```javascript
// Frontend (react-demo)
POST /proxy/platform/chat/async
{
  "source-ids": ["uuid-1", "uuid-2"],
  "user-config-params": {
    "userQuery": "Analyze the documents..."
  }
}
```

```python
# platform-api (users_auth.py:1234)
llm_payload = {
    "params": {
        "external_id": story_id,
        "source_ids": source_ids  # ✅ Included
    }
}
```

```python
# capitol-llm receives
{
  "params": {
    "external_id": "story-uuid",
    "source_ids": ["uuid-1", "uuid-2"]  # ✅ Used for retrieval
  }
}
```

## Files Modified

### platform-api
1. **`src/routes/users_auth.py`**:
   - Line 1234: Fixed source_ids bug in `generate_story()`
   - Lines 1310-1377: Added `upload_source_sync()` endpoint
   - Lines 1379-1459: Added `upload_source_file()` endpoint

### demo-proxy-app
2. **`test-source-upload.sh`**: New test script (executable)

## Testing

### Manual Testing

```bash
# 1. Upload JSON source with embedding
curl -X POST "http://localhost:8811/public/sources/upload-source/sync" \
  -H "Content-Type: application/json" \
  -H "X-User-ID: 1" \
  -H "X-API-Key: cap-dev-OPJC6oTQ-ebB7xRdd-7xydxD0C-oYVbyOYl" \
  -d '{
    "source-id": "'"$(uuidgen | tr '[:upper:]' '[:lower:]')"'",
    "filename": "climate-report.json",
    "generate-embedding": true,
    "tags": [{"Environment": "test"}],
    "data": {
      "title": "Climate Change Report",
      "content": "Rising temperatures are causing..."
    }
  }'

# Expected: {"source-id": "...", "embedding-status": "COMPLETED"}
```

```bash
# 2. Generate story with source
curl -X POST "http://localhost:8811/public/chat/async" \
  -H "Content-Type: application/json" \
  -H "X-User-ID: 1" \
  -H "X-API-Key: cap-dev-OPJC6oTQ-ebB7xRdd-7xydxD0C-oYVbyOYl" \
  -d '{
    "story-id": "'"$(uuidgen | tr '[:upper:]' '[:lower:]')"'",
    "source-ids": ["<source-id-from-step-1>"],
    "user-config-params": {
      "userQuery": "Analyze climate change based on the provided document",
      "format": "auto_mode"
    }
  }'

# Expected: {"external-id": "...", "socket-address": "ws://..."}
```

### Automated Testing

```bash
cd /Users/johnkealy/srv/capitol/demo-proxy-app
./test-source-upload.sh
```

**Expected output**:
- ✅ Source uploaded with UUID
- ✅ Embedding status: COMPLETED
- ✅ Story generation initiated with source IDs
- ✅ WebSocket address for monitoring

## Configuration

### Required Services

For the implementation to work, these services must be running:

1. **platform-api** (Port 8811)
   - Config: `CLOJURE_BASE_URL=http://clojure-api:3333`

2. **clj-services/gofapi** (Port 3333)
   - Handles actual S3 upload and Postgres writes
   - Calls Lambda for embedding generation

3. **capitol-llm** (Port 8300)
   - Receives source_ids in story generation
   - Retrieves embeddings from Qdrant

4. **Qdrant** (Vector database)
   - Stores document embeddings
   - Queried during story generation

5. **AWS Services**:
   - **S3 Buckets**:
     - `capitol-ai-user-documents` - PDF/image files
     - `capitol-ai-json-sources` - JSON documents
   - **Lambda**: `generate-embeddings` function

### Environment Variables

**platform-api**:
```bash
CLOJURE_BASE_URL=http://clojure-api:3333
CAPITOL_LLM_URL=http://capitol-llm
```

## What's Next

### Before Testing

1. **Ensure services are running**:
   ```bash
   # Check platform-api
   curl http://localhost:8811/docs

   # Check clj-services (from inside cluster)
   kubectl exec -it <platform-api-pod> -- curl http://clojure-api:3333/api/v1/sources
   ```

2. **Verify API key is valid**:
   ```bash
   # Test authentication
   curl -X GET "http://localhost:8811/public/user/current-user" \
     -H "X-User-ID: 1" \
     -H "X-API-Key: cap-dev-OPJC6oTQ-ebB7xRdd-7xydxD0C-oYVbyOYl"
   ```

3. **Check S3 access**:
   - Ensure clj-services can write to S3 buckets
   - Verify Lambda has permissions for embedding generation

### Testing Checklist

- [ ] Upload JSON source successfully
- [ ] Verify embedding status returns "COMPLETED"
- [ ] Check source record exists in Postgres
- [ ] Verify embedding exists in Qdrant
- [ ] Generate story with source-ids
- [ ] Confirm story uses uploaded source content
- [ ] Upload PDF file successfully
- [ ] Test with multiple sources

### Known Limitations

1. **File size limits**: Check clj-services multipart size limits
2. **Embedding timeout**: Large documents may timeout (currently 120s)
3. **S3 bucket access**: Requires proper AWS credentials
4. **Lambda cold starts**: First embedding may take longer

## Success Criteria

✅ **Complete** when:
1. JSON sources upload with embeddings
2. PDF files upload successfully
3. Source IDs pass through to capitol-llm
4. Stories generate using uploaded sources
5. Test script runs end-to-end without errors

## Related Documentation

- **GOFAPI_MIGRATION.md**: Overall gofapi → platform-api migration
- **SESSION_SUMMARY.md**: Previous session work on JWT auth
- **story-generation-flow.md**: Capitol-llm story generation architecture

## Contact

For questions about this implementation:
- Story generation flow: See `platform-api/docs/story-generation-flow.md`
- Source endpoints: Check `clj-services/gofapi/src/clj/gofapi/sources/routes.clj`
- Embedding logic: See `clj-services/gofapi/src/clj/gofapi/embeddings/model.clj`
