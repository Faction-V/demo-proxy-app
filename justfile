# Demo Proxy App - Justfile

# Default recipe - show available commands
default:
    @just --list

# Start the application
start:
    docker-compose up -d
    @echo "✓ Application started at http://localhost:8000"
    @echo "✓ API docs available at http://localhost:8000/docs"

# Stop the application
stop:
    docker-compose down
    @echo "✓ Application stopped"

# Restart the application
restart:
    docker-compose restart
    @echo "✓ Application restarted"

# View application logs
logs:
    docker-compose logs -f app

# Build the application
build:
    docker-compose build
    @echo "✓ Application built"

# Setup demo account with API key
setup-demo:
    @echo "Setting up demo account..."
    @echo ""
    @echo "1. Creating API key for demo organization..."
    @export API_KEY=$(curl -s -X POST "http://localhost:8811/internal-api-keys/f6fffb00-8fbc-4ec4-8d6b-f0e01154a253?env=dev" \
        -H "Content-Type: application/json" \
        -d '{"name": "Demo Proxy Key", "description": "API key for demo proxy application"}' \
        | grep -o '"api_key":"[^"]*"' | cut -d'"' -f4) && \
    if [ -n "$$API_KEY" ]; then \
        echo "✓ API Key created: $$API_KEY"; \
        echo ""; \
        echo "2. Updating .env file..."; \
        sed -i.bak "s|API_KEY=.*|API_KEY=$$API_KEY|g" .env; \
        echo "✓ .env file updated"; \
        echo ""; \
        echo "3. Restarting application..."; \
        docker-compose restart app > /dev/null 2>&1; \
        echo "✓ Application restarted"; \
        echo ""; \
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; \
        echo "✓ Demo account setup complete!"; \
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; \
        echo ""; \
        echo "Configuration:"; \
        echo "  - API URL: http://platform_api/public"; \
        echo "  - API Key: $$API_KEY"; \
        echo "  - Org ID: f6fffb00-8fbc-4ec4-8d6b-f0e01154a253"; \
        echo "  - Domain: https://aigrants.co/"; \
        echo ""; \
        echo "Proxy available at: http://localhost:8000"; \
        echo "API docs: http://localhost:8000/docs"; \
    else \
        echo "✗ Failed to create API key"; \
        echo "Make sure platform-api is running at http://localhost:8811"; \
        exit 1; \
    fi

# Create a new API key
create-api-key org_id="f6fffb00-8fbc-4ec4-8d6b-f0e01154a253" env="dev":
    @echo "Creating API key for organization {{org_id}}..."
    @curl -s -X POST "http://localhost:8811/internal-api-keys/{{org_id}}?env={{env}}" \
        -H "Content-Type: application/json" \
        -d '{"name": "Demo Proxy Key", "description": "API key for demo proxy application"}' | jq '.'

# List all API keys for an organization
list-api-keys org_id="f6fffb00-8fbc-4ec4-8d6b-f0e01154a253" env="dev":
    @echo "Fetching API keys for organization {{org_id}}..."
    @curl -s "http://localhost:8811/internal-api-keys/{{org_id}}?env={{env}}" | jq '.'

# Test the proxy with a sample request
test:
    @echo "Testing proxy connection..."
    @curl -s http://localhost:8000/api/health | jq '.' || echo "Proxy is running but endpoint may not exist"

# Check application status
status:
    @echo "Application Status:"
    @docker-compose ps
    @echo ""
    @echo "Environment Configuration:"
    @cat .env

# Clean up everything (stops containers and removes volumes)
clean:
    docker-compose down -v
    @echo "✓ Cleaned up containers and volumes"

# Full setup - build, start, and setup demo account
setup: build start
    @sleep 3
    @just setup-demo

# Update API key in .env and restart
update-api-key key:
    @echo "Updating API key..."
    @sed -i.bak "s|API_KEY=.*|API_KEY={{key}}|g" .env
    @docker-compose restart app
    @echo "✓ API key updated and application restarted"

# Show current configuration
config:
    @echo "Current Configuration:"
    @echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    @cat .env
    @echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Start React frontend
start-react:
    @echo "Starting React demo frontend..."
    @cd react-demo && \
    if [ ! -f .env ]; then echo "VITE_API_URL=http://localhost:8000" > .env; fi && \
    if [ ! -d node_modules ]; then npm install; fi && \
    npm run dev

# Start Vue frontend
start-vue:
    @echo "Starting Vue demo frontend..."
    @cd vue-demo && \
    if [ ! -f .env ]; then echo "VITE_API_URL=http://localhost:8000" > .env; fi && \
    if [ ! -d node_modules ]; then npm install; fi && \
    npm run dev

# Setup and start everything (backend + React frontend)
start-all: start
    @sleep 2
    @just start-react

# Full demo setup - backend + frontend
setup-full: setup
    @echo ""
    @echo "Starting React frontend..."
    @just start-react
