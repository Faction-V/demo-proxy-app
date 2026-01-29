#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Environment Configuration Check${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if .env exists
if [ ! -f .env ]; then
    echo -e "${YELLOW}⚠ .env file not found${NC}"
    echo ""
    echo "Creating .env from .env.sample..."
    cp .env.sample .env
    echo -e "${GREEN}✓ Created .env file${NC}"
    echo ""
    echo -e "${YELLOW}Action Required:${NC}"
    echo "  Run: ${BLUE}just setup-demo${NC} to configure API key"
    echo ""
    exit 1
fi

# Required environment variables
REQUIRED_VARS=("DOMAIN" "API_URL" "API_KEY")
MISSING_VARS=()
PLACEHOLDER_VARS=()

# Check each required variable
for var in "${REQUIRED_VARS[@]}"; do
    if ! grep -q "^${var}=" .env; then
        MISSING_VARS+=("$var")
    else
        # Get the value
        value=$(grep "^${var}=" .env | cut -d'=' -f2-)

        # Check if it's a placeholder or empty
        if [ -z "$value" ] || [[ "$value" == *"your-api-key-here"* ]] || [[ "$value" == *"REPLACE"* ]]; then
            PLACEHOLDER_VARS+=("$var")
        fi
    fi
done

# Report results
if [ ${#MISSING_VARS[@]} -eq 0 ] && [ ${#PLACEHOLDER_VARS[@]} -eq 0 ]; then
    echo -e "${GREEN}✓ All required environment variables are configured${NC}"
    echo ""
    echo "Current configuration:"
    echo "  DOMAIN: $(grep '^DOMAIN=' .env | cut -d'=' -f2-)"
    echo "  API_URL: $(grep '^API_URL=' .env | cut -d'=' -f2-)"
    echo "  API_KEY: $(grep '^API_KEY=' .env | cut -d'=' -f2- | cut -c1-20)..."
    echo ""
    echo -e "${GREEN}✓ Environment is ready!${NC}"
    exit 0
fi

# Report issues
if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    echo -e "${RED}✗ Missing environment variables:${NC}"
    for var in "${MISSING_VARS[@]}"; do
        echo "  - $var"
    done
    echo ""
fi

if [ ${#PLACEHOLDER_VARS[@]} -gt 0 ]; then
    echo -e "${YELLOW}⚠ Environment variables need configuration:${NC}"
    for var in "${PLACEHOLDER_VARS[@]}"; do
        echo "  - $var"
    done
    echo ""
fi

echo -e "${YELLOW}Action Required:${NC}"
if [[ " ${PLACEHOLDER_VARS[@]} " =~ " API_KEY " ]]; then
    echo "  Run: ${BLUE}just setup-demo${NC} to automatically configure API key"
else
    echo "  Update the .env file with correct values"
    echo "  Reference: .env.sample"
fi
echo ""

exit 1
