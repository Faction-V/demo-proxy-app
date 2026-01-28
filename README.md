
# DEMO PROXY API Proxy

This is a FastAPI application that acts as a proxy for forwarding requests to the Capitol API. It adds custom headers to the requests and logs the incoming and outgoing requests for debugging purposes.

## Introduction

The primary purpose of this application is to forward requests to a specified API URL while adding custom headers. It provides two main functionalities:

1. A dedicated endpoint `/forward-story` for forwarding a specific payload with custom headers.
2. A catch-all route `/api/{path:path}` that forwards any request (GET, POST, PUT, DELETE, PATCH) to the specified API URL, adding custom headers.

## Quick Start

### Prerequisites

- Docker and Docker Compose installed
- [Just](https://github.com/casey/just) command runner installed (optional but recommended)
- Platform API running at `http://localhost:8811`

### Setup with Just (Recommended)

```bash
# Full setup - build, start, and configure demo account
just setup

# Or step by step:
just build          # Build the Docker image
just start          # Start the application
just setup-demo     # Create API key and configure
```

### Manual Setup

1. Clone the repository:

```bash
git clone https://github.com/Faction-V/demo-proxy-app
cd demo-proxy-app
```

2. Build and start with Docker Compose:

```bash
docker-compose up -d
```

3. Create an API key (requires platform-api running):

```bash
curl -X POST "http://localhost:8811/internal-api-keys/f6fffb00-8fbc-4ec4-8d6b-f0e01154a253?env=dev" \
  -H "Content-Type: application/json" \
  -d '{"name": "Demo Proxy Key", "description": "API key for demo proxy application"}'
```

4. Update the `.env` file with the generated API key.

## Configuration

The application uses environment variables from the `.env` file:

- `API_URL`: The URL of the API to forward requests to (default: `http://platform_api/public`)
- `DOMAIN`: The domain value to be included in the `X-Domain` header
- `API_KEY`: The API key value to be included in the `X-API-Key` header

## Usage

### Accessing the Application

- **Proxy API**: http://localhost:8000
- **API Documentation**: http://localhost:8000/docs
- **Alternative Docs**: http://localhost:8000/redoc

### Available Endpoints

1. **POST /forward-story** - Forward a specific story payload with custom headers
2. **ANY /api/{path}** - Catch-all proxy that forwards any request to the configured API_URL

### Example Request

```bash
# Test the proxy
curl http://localhost:8000/api/organizations

# View logs
just logs
```

## Just Commands

### Backend Commands

```bash
just                    # Show all available commands
just setup              # Full setup (build + start + setup-demo)
just start              # Start the proxy application
just stop               # Stop the proxy application
just restart            # Restart the proxy application
just logs               # View application logs
just status             # Check application status
just config             # Show current configuration
just setup-demo         # Setup demo account with API key
just create-api-key     # Create a new API key
just list-api-keys      # List all API keys
just test               # Test the proxy connection
just clean              # Clean up containers and volumes
```

### Frontend Commands

```bash
just start-react        # Start React demo frontend
just start-vue          # Start Vue demo frontend
just start-all          # Start proxy + React frontend
just setup-full         # Full setup including frontend
```

## Frontend Applications

The repository includes two demo frontend applications:

### React Demo

- **Location**: `react-demo/`
- **URL**: http://localhost:5174
- **Start**: `just start-react` or `cd react-demo && npm run dev`

### Vue Demo

- **Location**: `vue-demo/`
- **URL**: http://localhost:5173
- **Start**: `just start-vue` or `cd vue-demo && npm run dev`

Both frontends are configured to connect to the proxy at `http://localhost:8000`.

## Manual Commands

### View Logs

```bash
docker-compose logs -f app
```

### Restart Application

```bash
docker-compose restart
```

### Stop Application

```bash
docker-compose down
```

## Contributing

Contributions are welcome! Please follow the standard GitHub workflow:

1. Fork the repository
2. Create a new branch
3. Make your changes
4. Open a pull request

## License

This project is licensed under the [MIT License](LICENSE).

