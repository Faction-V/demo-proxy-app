#!/bin/bash

# Test script for uploading documents with source embedding to platform-api
# This tests the complete flow: upload → embed → generate story with sources

set -e

# Configuration
BASE_URL="http://localhost:8811"
USER_ID="1"
API_KEY="cap-dev-OPJC6oTQ-ebB7xRdd-7xydxD0C-oYVbyOYl"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Source Upload and Story Generation Test ===${NC}\n"

# Generate UUIDs for source and story
SOURCE_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
STORY_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')

echo -e "${GREEN}Generated IDs:${NC}"
echo "Source ID: $SOURCE_ID"
echo "Story ID: $STORY_ID"
echo ""

# Step 1: Upload JSON source with embedding
echo -e "${BLUE}Step 1: Uploading JSON source with embedding...${NC}"

UPLOAD_RESPONSE=$(curl -s -X POST "${BASE_URL}/public/sources/upload-source/sync" \
  -H "Content-Type: application/json" \
  -H "X-User-ID: ${USER_ID}" \
  -H "X-API-Key: ${API_KEY}" \
  -d "{
    \"source-id\": \"${SOURCE_ID}\",
    \"filename\": \"test-document.json\",
    \"generate-embedding\": true,
    \"tags\": [{\"Environment\": \"test\"}],
    \"data\": {
      \"title\": \"Climate Change Impact Report\",
      \"content\": \"Climate change is one of the most pressing challenges facing humanity. Rising global temperatures are causing widespread environmental changes including melting ice caps, rising sea levels, and more frequent extreme weather events. Scientists agree that human activities, particularly the burning of fossil fuels, are the primary driver of recent climate change.\",
      \"category\": \"Environment\",
      \"date\": \"2024-01-15\"
    }
  }")

echo "$UPLOAD_RESPONSE" | jq '.'
echo ""

# Extract source-id from response
UPLOADED_SOURCE_ID=$(echo "$UPLOAD_RESPONSE" | jq -r '.["source-id"] // .source_id // empty')

if [ -z "$UPLOADED_SOURCE_ID" ]; then
  echo -e "${RED}Failed to upload source or extract source-id${NC}"
  exit 1
fi

echo -e "${GREEN}✓ Source uploaded successfully${NC}"
echo "Source ID: $UPLOADED_SOURCE_ID"
echo "Embedding Status: $(echo "$UPLOAD_RESPONSE" | jq -r '.["embedding-status"] // .embedding_status')"
echo ""

# Step 2: Wait for embedding to complete (if needed)
echo -e "${BLUE}Step 2: Waiting 5 seconds for embedding generation...${NC}"
sleep 5
echo ""

# Step 3: Generate story with the source
echo -e "${BLUE}Step 3: Generating story with source...${NC}"

STORY_RESPONSE=$(curl -s -X POST "${BASE_URL}/public/chat/async" \
  -H "Content-Type: application/json" \
  -H "X-User-ID: ${USER_ID}" \
  -H "X-API-Key: ${API_KEY}" \
  -d "{
    \"story-id\": \"${STORY_ID}\",
    \"source-ids\": [\"${UPLOADED_SOURCE_ID}\"],
    \"tags\": [{\"Environment\": \"test\"}],
    \"user-config-params\": {
      \"userQuery\": \"Create a comprehensive analysis of climate change impacts based on the provided source document\",
      \"format\": \"auto_mode\",
      \"responseModel\": \"claude-sonnet-4-5-20250929\",
      \"responseLength\": \"2 pages\",
      \"responseLanguage\": \"English\",
      \"generalWebSearch\": false,
      \"academicWebSearch\": false,
      \"aiImages\": true,
      \"headers\": true,
      \"paragraphs\": true,
      \"quotes\": true,
      \"lists\": true
    }
  }")

echo "$STORY_RESPONSE" | jq '.'
echo ""

# Extract story information
EXTERNAL_ID=$(echo "$STORY_RESPONSE" | jq -r '.["external-id"] // .external_id // .externalId // empty')
SOCKET_ADDRESS=$(echo "$STORY_RESPONSE" | jq -r '.["socket-address"] // .socket_address // .socketAddress // empty')

if [ -z "$EXTERNAL_ID" ]; then
  echo -e "${RED}Failed to generate story or extract external-id${NC}"
  exit 1
fi

echo -e "${GREEN}✓ Story generation initiated successfully${NC}"
echo "Story ID: $EXTERNAL_ID"
echo "WebSocket: $SOCKET_ADDRESS"
echo ""

# Step 4: Summary
echo -e "${BLUE}=== Test Summary ===${NC}"
echo -e "${GREEN}✓ All steps completed successfully${NC}"
echo ""
echo "What happened:"
echo "1. Uploaded JSON document as source with UUID: $UPLOADED_SOURCE_ID"
echo "2. Requested embedding generation for the source"
echo "3. Initiated story generation with source-ids: [$UPLOADED_SOURCE_ID]"
echo "4. Story generation started with ID: $EXTERNAL_ID"
echo ""
echo "Next steps:"
echo "- Monitor story generation via WebSocket: $SOCKET_ADDRESS"
echo "- Check story at frontend URL once generation completes"
echo "- Verify that the story includes information from the uploaded source"
echo ""

# Optional: Test file upload endpoint
echo -e "${BLUE}=== Optional: Test File Upload Endpoint ===${NC}"
echo "To test file upload, create a sample PDF and run:"
echo ""
echo "curl -X POST '${BASE_URL}/public/sources/upload-source/file' \\"
echo "  -H 'X-User-ID: ${USER_ID}' \\"
echo "  -H 'X-API-Key: ${API_KEY}' \\"
echo "  -F 'source-id=\$(uuidgen | tr \"[:upper:]\" \"[:lower:]\")' \\"
echo "  -F 'filename=sample.pdf' \\"
echo "  -F 'file=@/path/to/your/sample.pdf'"
echo ""
