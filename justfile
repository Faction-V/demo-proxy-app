# Demo Proxy App - Justfile

# Service directories (relative to parent directory)
_work_dir := parent_directory(justfile_directory())
platform_api_dir := _work_dir + "/platform-api"
clj_pg_wrapper_dir := _work_dir + "/clj-pg-wrapper"
capitol_llm_dir := _work_dir + "/capitol-llm"
demo_proxy_dir := justfile_directory()

# Colors for output
GREEN := '\033[0;32m'
YELLOW := '\033[1;33m'
BLUE := '\033[0;34m'
NC := '\033[0m' # No Color

# Helper function to run commands in other directories
_dir_command dir command:
    #!/usr/bin/env bash
    if [ -d {{ dir }} ]; then
        cd {{ dir }} && {{ command }}
    else
        echo "{{ dir }} directory does not exist, skipping"
    fi

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

# Setup and start everything (all services + React frontend)
start-all: start-services
    @sleep 2
    @just start-react

# Full demo setup - backend + frontend
setup-full: setup
    @echo ""
    @echo "Starting React frontend..."
    @just start-react

# Start all required services for foreign user auth demo (platform-api, clj-pg-wrapper, capitol-llm, demo-proxy-app)
start-services:
    #!/usr/bin/env bash
    set -e
    echo -e "{{ BLUE }}========================================{{ NC }}"
    echo -e "{{ BLUE }}Starting Foreign User Auth Demo Services{{ NC }}"
    echo -e "{{ BLUE }}========================================{{ NC }}"
    echo ""

    # Check if parallel is installed
    if ! command -v parallel &> /dev/null; then
        echo -e "{{ YELLOW }}⚠ GNU parallel not installed, starting services sequentially...{{ NC }}"
        echo ""
        echo -e "{{ YELLOW }}Starting platform-api...{{ NC }}"
        just _dir_command {{ platform_api_dir }} 'just up'
        echo -e "{{ YELLOW }}Starting clj-pg-wrapper...{{ NC }}"
        just _dir_command {{ clj_pg_wrapper_dir }} 'just up'
        echo -e "{{ YELLOW }}Starting capitol-llm...{{ NC }}"
        just _dir_command {{ capitol_llm_dir }} 'just up'
        echo -e "{{ YELLOW }}Starting demo-proxy-app...{{ NC }}"
        just start
    else
        echo -e "{{ YELLOW }}Starting services in parallel...{{ NC }}"
        echo ""
        parallel -j4 --tag --lb --tty --tagstring '\033[3{%}m[Job {%}] [{}]\033[0m' \
        "just _dir_command {} 'just up'" ::: {{ platform_api_dir }} {{ clj_pg_wrapper_dir }} {{ capitol_llm_dir }}
        echo ""
        echo -e "{{ YELLOW }}Starting demo-proxy-app...{{ NC }}"
        just start
    fi

    echo ""
    echo -e "{{ GREEN }}========================================{{ NC }}"
    echo -e "{{ GREEN }}✓ All services started!{{ NC }}"
    echo -e "{{ GREEN }}========================================{{ NC }}"
    echo ""
    echo -e "{{ BLUE }}Services running on:{{ NC }}"
    echo -e "  • Platform API:      {{ YELLOW }}http://localhost:8811{{ NC }} (docs: http://localhost:8811/docs)"
    echo -e "  • CLJ PG Wrapper:    {{ YELLOW }}http://localhost:8400{{ NC }}"
    echo -e "  • Capitol LLM:       {{ YELLOW }}http://localhost:8003{{ NC }}"
    echo -e "  • Demo Proxy App:    {{ YELLOW }}http://localhost:8000{{ NC }} (docs: http://localhost:8000/docs)"
    echo ""
    echo -e "{{ YELLOW }}Next steps:{{ NC }}"
    echo "  1. Run: just setup-demo        # Configure API key"
    echo "  2. Run: ./test-foreign-user.sh # Test foreign user authentication"
    echo ""

# Stop all services (platform-api, clj-pg-wrapper, capitol-llm, demo-proxy-app)
stop-services:
    #!/usr/bin/env bash
    echo -e "{{ YELLOW }}Stopping all services...{{ NC }}"
    echo ""

    # Check if parallel is installed
    if ! command -v parallel &> /dev/null; then
        just _dir_command {{ platform_api_dir }} 'just down'
        just _dir_command {{ clj_pg_wrapper_dir }} 'just down'
        just _dir_command {{ capitol_llm_dir }} 'just down'
        just stop
    else
        parallel -j4 --tag --lb --tty --tagstring '\033[3{%}m[Job {%}] [{}]\033[0m' \
        "just _dir_command {} 'just down'" ::: {{ platform_api_dir }} {{ clj_pg_wrapper_dir }} {{ capitol_llm_dir }}
        just stop
    fi

    echo ""
    echo -e "{{ GREEN }}✓ All services stopped{{ NC }}"

# Run the foreign user authentication test
test-foreign-auth:
    #!/usr/bin/env bash
    if [ ! -f test-foreign-user.sh ]; then
        echo -e "{{ YELLOW }}⚠ test-foreign-user.sh not found{{ NC }}"
        exit 1
    fi
    chmod +x test-foreign-user.sh
    ./test-foreign-user.sh

# Full demo: start services, setup, and run tests
demo-full:
    @echo -e "{{ BLUE }}========================================{{ NC }}"
    @echo -e "{{ BLUE }}Foreign User Auth - Full Demo{{ NC }}"
    @echo -e "{{ BLUE }}========================================{{ NC }}"
    @echo ""
    just start-services
    @sleep 5
    @echo -e "{{ YELLOW }}Configuring API key...{{ NC }}"
    just setup-demo
    @echo ""
    @echo -e "{{ YELLOW }}Running authentication tests...{{ NC }}"
    @sleep 2
    just test-foreign-auth
