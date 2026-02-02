import os
import logging
from fastapi import FastAPI, Request, Response
from pydantic import BaseModel
import httpx
import json
from datetime import datetime
import uuid
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker


app = FastAPI()

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

# Database connection for fetching sources
DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://postgres:postgres@localhost:5432/postgres")

# Create SQLAlchemy engine
engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def get_user_source_ids(user_id: str) -> list[str]:
    """
    Fetch all source IDs for a given user from the database.

    Args:
        user_id: The user ID to fetch sources for

    Returns:
        List of source ID strings
    """
    try:
        with SessionLocal() as session:
            # Query for all recent sources (simplified for testing)
            # TODO: Add proper org_id or user_id filtering once auth is properly mapped
            query = text("""
                SELECT id FROM sources
                ORDER BY created_at DESC
                LIMIT 10
            """)
            result = session.execute(query)
            source_ids = [str(row[0]) for row in result.fetchall()]
            logging.info(f"Found {len(source_ids)} source IDs (all recent): {source_ids}")
            return source_ids
    except Exception as e:
        logging.error(f"Error fetching source IDs: {e}")
        return []


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
    logging.info(f"****")
    logging.info(f"Timestamp: {timestamp} Stack ID: {stack_id} Custom Headers: {dict(custom_headers)}")

    # Intercept /chat/async requests to inject source IDs
    modified_body = body
    if path.endswith("chat/async") and request.method == "POST":
        try:
            # Parse the JSON body
            body_json = json.loads(body.decode('utf-8'))

            # Get the user ID from headers
            user_id = custom_headers.get("X-User-ID", USER_ID)

            # Fetch all source IDs for this user
            source_ids = get_user_source_ids(user_id)

            if source_ids:
                # Add source-ids to the payload
                body_json["source-ids"] = source_ids
                logging.info(f"Timestamp: {timestamp} Stack ID: {stack_id} Injected {len(source_ids)} source IDs into chat/async request: {source_ids}")

                # Convert back to bytes
                modified_body = json.dumps(body_json).encode('utf-8')
            else:
                logging.info(f"Timestamp: {timestamp} Stack ID: {stack_id} No sources found for user {user_id}, forwarding request without source-ids")
        except Exception as e:
            logging.error(f"Timestamp: {timestamp} Stack ID: {stack_id} Error injecting source IDs: {e}")
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
