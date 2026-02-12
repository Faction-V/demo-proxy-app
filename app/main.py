import os
import logging
import asyncio
from contextlib import asynccontextmanager
from pathlib import Path
from fastapi import FastAPI, Request, Response
from pydantic import BaseModel
import httpx
import json
from datetime import datetime
import uuid


# Setup logging
logging.basicConfig(level=logging.INFO)

# Get the API URL and other variables from environment variables
FORWARD_URL = os.getenv(
    "API_URL", "https://example.com"
)  # Replace with your default or environment variable
X_DOMAIN = os.getenv(
    "DOMAIN", "your-default-domain"
)  # Replace with your domain or environment variable
X_API_KEY = os.getenv(
    "API_KEY", "your-default-api-key"
)  # Replace with your API key or environment variable
USER_ID = "1"  # Hardcoded user ID

# Path to persisted source ID
SOURCE_ID_FILE = Path("/app/source_id.json")
SAMPLE_SOURCE_FILE = Path(__file__).parent / "sample_source.txt"


async def upload_sample_source():
    """Upload the sample source document to platform-api on startup."""
    source_id = str(uuid.uuid4())
    filename = "sample_source.txt"

    try:
        content = SAMPLE_SOURCE_FILE.read_text()
    except FileNotFoundError:
        logging.error(f"Sample source file not found: {SAMPLE_SOURCE_FILE}")
        return

    upload_url = f"{FORWARD_URL}/sources/upload-source/sync"
    headers = {
        "X-API-Key": X_API_KEY,
        "X-User-ID": USER_ID,
        "X-Domain": X_DOMAIN,
        "Content-Type": "application/json",
    }
    payload = {
        "source-id": source_id,
        "filename": filename,
        "data": {
            "meta": {
                "title": "Renewable Energy: A Comprehensive Overview",
                "filename": filename,
            },
            "content": content,
        },
        "generate-embedding": True,
    }

    # Retry with backoff until platform-api is ready
    for attempt in range(30):
        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                response = await client.post(upload_url, json=payload, headers=headers)

            if response.status_code == 200:
                result = response.json()
                source_data = {
                    "source_id": source_id,
                    "filename": filename,
                    "upload_response": result,
                }
                SOURCE_ID_FILE.write_text(json.dumps(source_data, indent=2))
                logging.info(f"Source uploaded successfully. ID: {source_id}")
                logging.info(f"Source data written to {SOURCE_ID_FILE}")
                return
            else:
                logging.warning(
                    f"Source upload attempt {attempt + 1} failed ({response.status_code}): {response.text}"
                )
        except Exception as e:
            logging.warning(f"Source upload attempt {attempt + 1} error: {e}")

        await asyncio.sleep(2)

    logging.error("Failed to upload sample source after 30 attempts")


def get_source_for_injection() -> list[dict] | None:
    """Read the persisted source ID and return injection payload.

    Capitol-llm validates that each entry has exactly {"download_url", "filename"}.
    """
    try:
        if not SOURCE_ID_FILE.exists():
            return None

        source_data = json.loads(SOURCE_ID_FILE.read_text())
        filename = source_data["filename"]

        # Get the embedded parquet URL from the upload response
        upload_response = source_data.get("upload_response", {})
        download_url = upload_response.get("download_url") or upload_response.get("embedded_file_url", "")

        if not download_url:
            logging.warning("No download_url found in source data, skipping injection")
            return None

        # Capitol-llm expects exactly {download_url, filename} — no extra keys
        # Use the parquet filename from the URL (matches production pattern)
        parquet_filename = download_url.split("/")[-1] if "/" in download_url else filename
        return [{
            "download_url": download_url,
            "filename": parquet_filename,
        }]
    except Exception as e:
        logging.error(f"Error reading source ID file: {e}")
        return None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Upload sample source on startup."""
    logging.info("Starting source upload...")
    asyncio.create_task(upload_sample_source())
    yield


app = FastAPI(lifespan=lifespan)


# Define the request model for the specific POST request
class StoryPayload(BaseModel):
    story_id: str
    user_config_params: dict
    story_plan_config_id: str


# Helper function to add required headers
def add_custom_headers(original_content_type=None, incoming_headers=None):
    """
    Add custom headers for API requests following the clojure middleware pattern.

    Args:
        original_content_type: Content-Type from the original request
        incoming_headers: Headers from the incoming request to pass through
    """
    # Start with default headers (matching clojure middleware pattern)
    headers = {
        "X-Domain": X_DOMAIN,
        "X-API-Key": X_API_KEY,  # API key for authentication
        "X-User-ID": USER_ID,     # Default foreign user identifier
        "Accept": "application/json",
    }

    # Pass through X-User-ID if provided in incoming request
    if incoming_headers and "x-user-id" in incoming_headers:
        headers["X-User-ID"] = incoming_headers["x-user-id"]

    # Only add Content-Type if specified, allowing multipart and other types
    if original_content_type:
        headers["Content-Type"] = original_content_type

    return headers


# POST endpoint for forwarding the specific payload
@app.post("/forward-story")
async def forward_story(payload: StoryPayload):
    headers = add_custom_headers()  # Add custom headers

    async with httpx.AsyncClient(timeout=10.0) as client:
        response = await client.post(
            url=FORWARD_URL,
            json=payload.dict(),  # Forward the request payload as JSON
            headers=headers,  # Include the custom headers
        )
        return Response(
            content=response.text,
            status_code=response.status_code,
            headers=dict(response.headers),
        )


# Catch-all route that forwards any request (with method, params, and body)
@app.api_route("/api/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "PATCH"])
async def catch_all(request: Request, path: str):

    stack_id = str(uuid.uuid4())

    # Strip /v1/ prefix if present (React library adds it, but platform-api doesn't use it)
    if path.startswith("v1/"):
        path = path[3:]  # Remove "v1/"

    # Construct the full URL to forward the request
    forward_url = f"{FORWARD_URL}/{path}"
    # Extract query params
    query_params = request.url.query
    client_ip = request.client.host if request.client else "Unknown"

    # Log the incoming request details for debugging
    timestamp = datetime.now().isoformat()  # ISO 8601 timestamp
    logging.info(f'Timestamp: {timestamp} Stack ID: {stack_id} Client IP: {client_ip} Forwarded URL: {forward_url}')
    logging.info(f'Timestamp: {timestamp} Stack ID: {stack_id} Client IP: {client_ip} Incoming request: {request.method} {request.url}')
    logging.info(f'Timestamp: {timestamp} Stack ID: {stack_id} Client IP: {client_ip} Headers: {dict(request.headers)}')
    logging.info(f'Timestamp: {timestamp} Stack ID: {stack_id} Client IP: {client_ip} Query params: {query_params}')


    try:
        body = await request.body()
        logging.info(f"Body: {body.decode('utf-8')}")
    except Exception as e:
        logging.error(f"Error reading body: {e}")

    # Get the original content type from the request
    original_content_type = request.headers.get("Content-Type")
    custom_headers = add_custom_headers(original_content_type, incoming_headers=request.headers)

    # Add X-Forwarded-Host for WebSocket address generation
    # This allows platform-api to return the correct external WebSocket URL
    custom_headers["X-Forwarded-Host"] = request.headers.get("host", "localhost:8000")

    logging.info(f"****")
    logging.info(f"Timestamp: {timestamp} Stack ID: {stack_id} Custom Headers: {dict(custom_headers)}")

    # Intercept /chat/async requests to inject source documents
    modified_body = body
    if path.endswith("chat/async") and request.method == "POST":
        try:
            body_json = json.loads(body.decode('utf-8'))

            # Read source from file (uploaded on startup)
            sources = get_source_for_injection()

            if sources:
                if "user-config-params" not in body_json:
                    body_json["user-config-params"] = {}

                body_json["user-config-params"]["user_pre_processed_sources"] = sources
                logging.info(f"Timestamp: {timestamp} Stack ID: {stack_id} Injected {len(sources)} pre-processed sources into chat/async request")
                logging.info(f"Timestamp: {timestamp} Stack ID: {stack_id} Sources: {sources}")

                modified_body = json.dumps(body_json).encode('utf-8')
            else:
                logging.info(f"Timestamp: {timestamp} Stack ID: {stack_id} No source ID file found, forwarding request without sources")
        except Exception as e:
            logging.error(f"Timestamp: {timestamp} Stack ID: {stack_id} Error injecting source documents: {e}")
            # Continue with original body if there's an error

    async with httpx.AsyncClient(timeout=10.0) as client:
        response = await client.request(
            method=request.method,
            url=f"{forward_url}?{query_params}",
            headers=custom_headers,  # Add custom headers here
            content=modified_body,
        )

    # Log the response for debugging
    logging.info(f"Timestamp: {timestamp} Stack ID: {stack_id} Forwarded response status: {response.status_code}")
    logging.info(f"Timestamp: {timestamp} Stack ID: {stack_id} Response content: {response.text}")

    # Return the response from the forwarded request, preserving the status code and headers
    # Return the response with JSON content and status code

    try:
        json_content = response.json()
        return Response(
            content=json.dumps(json_content),
            status_code=response.status_code,
            headers={"Content-Type": "application/json"},
        )
    except ValueError:
        # If the response is not JSON, fallback to returning it as text
        logging.error("Response content is not valid JSON")
        return Response(
            content=response.text,
            status_code=response.status_code,
            headers={
                "Content-Type": response.headers.get("Content-Type", "text/plain")
            },
        )
