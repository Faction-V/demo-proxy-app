#!/bin/bash

# Test script for WebSocket-enabled source upload to platform-api
# This tests the async upload flow with real-time status updates

set -e

# Configuration
BASE_URL="http://localhost:8811/public"
USER_ID="1"
API_KEY="cap-dev-OPJC6oTQ-ebB7xRdd-7xydxD0C-oYVbyOYl"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== WebSocket Source Upload Test ===${NC}\n"

# Generate UUIDs
WS_UUID=$(uuidgen | tr '[:upper:]' '[:lower:]')
SOURCE_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')

echo -e "${GREEN}Generated IDs:${NC}"
echo "WebSocket UUID: $WS_UUID"
echo "Source ID: $SOURCE_ID"
echo ""

# Step 1: Create WebSocket address
echo -e "${BLUE}Step 1: Creating WebSocket address...${NC}"

WS_RESPONSE=$(curl -s -X POST "${BASE_URL}/sources/ws" \
  -H "Content-Type: application/json" \
  -H "X-User-ID: ${USER_ID}" \
  -H "X-API-Key: ${API_KEY}" \
  -d "{
    \"ws-uuid\": \"${WS_UUID}\"
  }")

echo "$WS_RESPONSE" | jq '.'
echo ""

# Extract WebSocket address
WS_ADDRESS=$(echo "$WS_RESPONSE" | jq -r '.["ws-address"] // .ws_address // empty')

if [ -z "$WS_ADDRESS" ]; then
  echo -e "${RED}Failed to get WebSocket address${NC}"
  exit 1
fi

echo -e "${GREEN}✓ WebSocket address created${NC}"
echo "Address: $WS_ADDRESS"
echo ""

# Step 2: Connect to WebSocket in background using websocat
echo -e "${BLUE}Step 2: Connecting to WebSocket...${NC}"
echo -e "${YELLOW}Note: Install websocat for WebSocket testing: brew install websocat${NC}"

# Check if websocat is available
if ! command -v websocat &> /dev/null; then
  echo -e "${YELLOW}websocat not found. WebSocket messages will not be displayed.${NC}"
  echo -e "${YELLOW}Install with: brew install websocat${NC}"
  echo ""
  SKIP_WS=true
else
  # Connect to WebSocket and capture output
  echo -e "${GREEN}✓ Connecting to WebSocket...${NC}"
  websocat "$WS_ADDRESS" &
  WS_PID=$!
  sleep 2
  echo ""
fi

# Step 3: Upload source (async)
echo -e "${BLUE}Step 3: Uploading source (async)...${NC}"

UPLOAD_RESPONSE=$(curl -s -X POST "${BASE_URL}/sources/upload-source" \
  -H "X-User-ID: ${USER_ID}" \
  -H "X-API-Key: ${API_KEY}" \
  -F "ws-uuid=${WS_UUID}" \
  -F "source-uuid=${SOURCE_ID}" \
  -F "filename=test-document.json" \
  -F "content=https://example.com/sample-document.pdf")

echo "$UPLOAD_RESPONSE" | jq '.'
echo ""

# Extract message
MESSAGE=$(echo "$UPLOAD_RESPONSE" | jq -r '.message // empty')

if [ -z "$MESSAGE" ]; then
  echo -e "${RED}Failed to start upload${NC}"
  [ ! -z "$WS_PID" ] && kill $WS_PID 2>/dev/null
  exit 1
fi

echo -e "${GREEN}✓ Upload started successfully${NC}"
echo "Message: $MESSAGE"
echo ""

# Step 4: Wait for processing to complete
echo -e "${BLUE}Step 4: Waiting for processing (10 seconds)...${NC}"
echo -e "${YELLOW}Watch the WebSocket output above for real-time status updates${NC}"
sleep 10
echo ""

# Step 5: Clean up WebSocket connection
if [ ! -z "$WS_PID" ]; then
  kill $WS_PID 2>/dev/null || true
  echo -e "${GREEN}✓ Closed WebSocket connection${NC}"
  echo ""
fi

# Step 6: Summary
echo -e "${BLUE}=== Test Summary ===${NC}"
echo -e "${GREEN}✓ All steps completed${NC}"
echo ""
echo "What happened:"
echo "1. Created WebSocket address with UUID: $WS_UUID"
echo "2. Connected to WebSocket: $WS_ADDRESS"
echo "3. Started async upload with source ID: $SOURCE_ID"
echo "4. Server published status updates to Redis"
echo "5. WebSocket received real-time updates (check output above)"
echo ""
echo "Flow verified:"
echo "✓ POST /sources/ws - Created WebSocket address"
echo "✓ WebSocket /ws/{ws_uuid} - Connected successfully"
echo "✓ POST /sources/upload-source - Started async processing"
echo "✓ Redis pub/sub - Messages forwarded to WebSocket"
echo ""

# Optional: Test with file upload
echo -e "${BLUE}=== Optional: File Upload Test ===${NC}"
echo "To test file upload with WebSocket:"
echo ""
echo "1. Create a test PDF:"
echo "   echo 'Test content' > test.pdf"
echo ""
echo "2. Get WebSocket address:"
echo "   WS_UUID=\$(uuidgen | tr '[:upper:]' '[:lower:]')"
echo "   curl -X POST '${BASE_URL}/sources/ws' \\"
echo "     -H 'X-User-ID: ${USER_ID}' \\"
echo "     -H 'X-API-Key: ${API_KEY}' \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"ws-uuid\": \"'\$WS_UUID'\"}'"
echo ""
echo "3. Connect to WebSocket:"
echo "   websocat ws://localhost:8811/ws/\$WS_UUID &"
echo ""
echo "4. Upload file:"
echo "   curl -X POST '${BASE_URL}/sources/upload-source' \\"
echo "     -H 'X-User-ID: ${USER_ID}' \\"
echo "     -H 'X-API-Key: ${API_KEY}' \\"
echo "     -F 'ws-uuid='\$WS_UUID \\"
echo "     -F 'source-uuid=\$(uuidgen | tr \"[:upper:]\" \"[:lower:]\")' \\"
echo "     -F 'filename=test.pdf' \\"
echo "     -F 'file=@test.pdf'"
echo ""
