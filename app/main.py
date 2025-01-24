import os
import logging
from fastapi import FastAPI, Request, Response
from pydantic import BaseModel
import httpx
import json
from datetime import datetime
import uuid


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


# Define the request model for the specific POST request
class StoryPayload(BaseModel):
    story_id: str
    user_config_params: dict
    story_plan_config_id: str


# Helper function to add required headers
def add_custom_headers(original_content_type=None):
    headers = {
        "X-Domain": X_DOMAIN,
        "X-API-Key": X_API_KEY,
        "X-User-ID": USER_ID,
        "Accept": "application/json",
        # "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
    }
    
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
    # Construct the full URL to forward the request
    forward_url = f"{FORWARD_URL}/api/{path}"
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
    custom_headers = add_custom_headers(original_content_type)
    logging.info(f"****")
    logging.info(f"Timestamp: {timestamp} Stack ID: {stack_id} Custom Headers: {dict(custom_headers)}")
    
    async with httpx.AsyncClient(timeout=10.0) as client:
        response = await client.request(
            method=request.method,
            url=f"{forward_url}?{query_params}",
            headers=custom_headers,  # Add custom headers here
            content=body,
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
