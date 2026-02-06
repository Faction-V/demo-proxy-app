# WebSocket Source Upload - Quick Start Guide

## TL;DR

Upload files with real-time status updates in 3 steps:

```bash
# 1. Get WebSocket address
WS_UUID=$(uuidgen | tr '[:upper:]' '[:lower:]')
curl -X POST 'http://localhost:8811/public/sources/ws' \
  -H 'X-User-ID: 1' \
  -H 'X-API-Key: YOUR_API_KEY' \
  -d "{\"ws-uuid\": \"$WS_UUID\"}"

# 2. Connect to WebSocket
websocat ws://localhost:8811/ws/$WS_UUID &

# 3. Upload file
curl -X POST 'http://localhost:8811/public/sources/upload-source' \
  -H 'X-User-ID: 1' \
  -H 'X-API-Key: YOUR_API_KEY' \
  -F "ws-uuid=$WS_UUID" \
  -F "source-uuid=$(uuidgen | tr '[:upper:]' '[:lower:]')" \
  -F "file=@document.pdf"
```

## JavaScript Client Example

```javascript
// 1. Create WebSocket address
const wsUuid = crypto.randomUUID();
const response = await fetch('http://localhost:8811/public/sources/ws', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'X-User-ID': '1',
    'X-API-Key': 'YOUR_API_KEY'
  },
  body: JSON.stringify({ 'ws-uuid': wsUuid })
});

const { 'ws-address': wsAddress } = await response.json();

// 2. Connect to WebSocket
const ws = new WebSocket(wsAddress);

ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  console.log('Status update:', data);

  if (data.status === 'success') {
    console.log('Upload complete:', data.result);
  } else if (data.status === 'failure') {
    console.error('Upload failed:', data.error);
  }
};

// 3. Upload file
const formData = new FormData();
formData.append('ws-uuid', wsUuid);
formData.append('source-uuid', crypto.randomUUID());
formData.append('file', fileInput.files[0]);

await fetch('http://localhost:8811/public/sources/upload-source', {
  method: 'POST',
  headers: {
    'X-User-ID': '1',
    'X-API-Key': 'YOUR_API_KEY'
  },
  body: formData
});
```

## Python Client Example

```python
import asyncio
import uuid
import websockets
import aiohttp

async def upload_with_websocket(file_path: str, api_key: str):
    # 1. Create WebSocket address
    ws_uuid = str(uuid.uuid4())

    async with aiohttp.ClientSession() as session:
        async with session.post(
            'http://localhost:8811/public/sources/ws',
            json={'ws-uuid': ws_uuid},
            headers={
                'X-User-ID': '1',
                'X-API-Key': api_key
            }
        ) as resp:
            data = await resp.json()
            ws_address = data['ws-address']

    # 2. Connect to WebSocket
    async with websockets.connect(ws_address) as websocket:
        # 3. Upload file
        source_uuid = str(uuid.uuid4())

        async with aiohttp.ClientSession() as session:
            data = aiohttp.FormData()
            data.add_field('ws-uuid', ws_uuid)
            data.add_field('source-uuid', source_uuid)
            data.add_field('file', open(file_path, 'rb'))

            async with session.post(
                'http://localhost:8811/public/sources/upload-source',
                data=data,
                headers={
                    'X-User-ID': '1',
                    'X-API-Key': api_key
                }
            ) as resp:
                print(f"Upload started: {await resp.json()}")

        # 4. Listen for updates
        async for message in websocket:
            data = json.loads(message)
            print(f"Status: {data}")

            if data.get('status') in ['success', 'failure']:
                break

# Run
asyncio.run(upload_with_websocket('document.pdf', 'YOUR_API_KEY'))
```

## React Hook Example

```typescript
import { useState, useEffect, useRef } from 'react';

function useWebSocketUpload(apiKey: string) {
  const [status, setStatus] = useState<string>('idle');
  const [result, setResult] = useState<any>(null);
  const [error, setError] = useState<string | null>(null);
  const wsRef = useRef<WebSocket | null>(null);

  const uploadFile = async (file: File) => {
    try {
      setStatus('connecting');

      // 1. Create WebSocket address
      const wsUuid = crypto.randomUUID();
      const wsResponse = await fetch('http://localhost:8811/public/sources/ws', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-User-ID': '1',
          'X-API-Key': apiKey,
        },
        body: JSON.stringify({ 'ws-uuid': wsUuid }),
      });

      const { 'ws-address': wsAddress } = await wsResponse.json();

      // 2. Connect to WebSocket
      const ws = new WebSocket(wsAddress);
      wsRef.current = ws;

      ws.onopen = async () => {
        setStatus('uploading');

        // 3. Upload file
        const formData = new FormData();
        formData.append('ws-uuid', wsUuid);
        formData.append('source-uuid', crypto.randomUUID());
        formData.append('file', file);

        await fetch('http://localhost:8811/public/sources/upload-source', {
          method: 'POST',
          headers: {
            'X-User-ID': '1',
            'X-API-Key': apiKey,
          },
          body: formData,
        });
      };

      ws.onmessage = (event) => {
        const data = JSON.parse(event.data);

        if (data.status === 'processing') {
          setStatus('processing');
        } else if (data.status === 'success') {
          setStatus('success');
          setResult(data.result);
          ws.close();
        } else if (data.status === 'failure') {
          setStatus('error');
          setError(data.error);
          ws.close();
        }
      };

      ws.onerror = () => {
        setStatus('error');
        setError('WebSocket connection error');
      };

    } catch (err) {
      setStatus('error');
      setError(err instanceof Error ? err.message : 'Unknown error');
    }
  };

  useEffect(() => {
    return () => {
      wsRef.current?.close();
    };
  }, []);

  return { uploadFile, status, result, error };
}

// Usage
function FileUploader() {
  const { uploadFile, status, result, error } = useWebSocketUpload('YOUR_API_KEY');

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      uploadFile(file);
    }
  };

  return (
    <div>
      <input type="file" onChange={handleFileChange} />
      <div>Status: {status}</div>
      {result && <div>Result: {JSON.stringify(result)}</div>}
      {error && <div>Error: {error}</div>}
    </div>
  );
}
```

## Message Format

### Status Updates

**Processing:**
```json
{
  "step": "Hello, I start to process this source: abc-123",
  "status": 200,
  "step-status": "processing"
}
```

```json
{
  "message": "Source received. Starting to processing",
  "type": "file-upload",
  "source-uuid": "abc-123",
  "status": "processing"
}
```

**Success:**
```json
{
  "result": {
    "source-id": "abc-123",
    "filename": "document.pdf",
    "url": "https://...",
    "size": 12345
  },
  "type": "file-upload",
  "source-uuid": "abc-123",
  "status": "success"
}
```

**Failure:**
```json
{
  "result": "Error",
  "error": "File too large",
  "type": "file-upload",
  "source-uuid": "abc-123",
  "status": "failure"
}
```

## Common Issues

### WebSocket Connection Fails
```bash
# Check if platform-api is running
docker ps | grep platform_api

# Check if Redis is running
docker ps | grep redis

# Test WebSocket endpoint
curl -X POST 'http://localhost:8811/public/sources/ws' \
  -H 'X-User-ID: 1' \
  -H 'X-API-Key: YOUR_API_KEY' \
  -d '{"ws-uuid": "test-123"}'
```

### No Status Updates Received
```bash
# Check Redis pub/sub
docker exec -it platform-redis-cache redis-cli
> SUBSCRIBE test-123
> # Should see messages when upload starts
```

### Upload Hangs
```bash
# Check platform-api logs
docker logs platform_api -f

# Look for:
# - "WebSocket connected for ws_uuid: ..."
# - "Published to channel '...':"
# - "Forwarded message to WebSocket: ..."
```

## Performance Tips

1. **Reuse WebSocket:** Create one WebSocket for multiple uploads
2. **Connection Pooling:** Limit concurrent WebSocket connections
3. **Timeout:** Set reasonable timeouts (5-10 min for large files)
4. **Error Handling:** Always handle WebSocket errors and reconnection
5. **Clean Up:** Close WebSocket connections when done

## Testing Checklist

- [ ] Upload PDF file (< 10MB)
- [ ] Upload large PDF (> 50MB)
- [ ] Upload via URL
- [ ] Handle connection errors
- [ ] Handle timeout
- [ ] Multiple concurrent uploads
- [ ] Upload with invalid auth
- [ ] Upload with missing ws-uuid

## API Reference

### POST /public/sources/ws

Create WebSocket address for receiving upload status updates.

**Headers:**
- `X-User-ID`: User identifier
- `X-API-Key`: API key for authentication

**Body:**
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

### WebSocket /ws/{ws_uuid}

Connect to WebSocket for real-time upload status updates.

**URL:** `ws://localhost:8811/ws/{ws_uuid}`

**Messages:** JSON-encoded status updates (see Message Format above)

**Connection:** Automatically closes after "success" or "failure" status

### POST /public/sources/upload-source

Upload source file or URL with WebSocket status updates.

**Headers:**
- `X-User-ID`: User identifier
- `X-API-Key`: API key for authentication

**Body (multipart/form-data):**
- `ws-uuid`: WebSocket UUID from /sources/ws
- `source-uuid`: Unique identifier for this source
- `filename`: Name of the file (optional)
- `file`: File data (for file uploads)
- `content`: URL (for URL uploads)

**Response:**
```json
{
  "message": "Processing file: 550e8400-e29b-41d4-a716-446655440000"
}
```

## More Information

- [Full Documentation](./WEBSOCKET_SOURCE_UPLOAD.md)
- [Migration Summary](./WEBSOCKET_MIGRATION_SUMMARY.md)
- [Test Script](./test-websocket-upload.sh)
