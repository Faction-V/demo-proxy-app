"""Shared fixtures for e2e tests.

These tests hit the running demo-proxy-app at localhost:8000 and validate
the full request path through to platform-api and its downstream services.

Required: all services running (just start-services && just setup-demo).
"""

import os
from typing import Dict
import pytest
import httpx


def _load_dotenv() -> Dict[str, str]:
    """Minimal .env loader — no third-party dependency needed."""
    env_path = os.path.join(os.path.dirname(__file__), os.pardir, ".env")
    vals: Dict[str, str] = {}
    try:
        with open(env_path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                key, _, value = line.partition("=")
                if key and value:
                    vals[key.strip()] = value.strip()
    except FileNotFoundError:
        pass
    return vals


_env = _load_dotenv()

PROXY_BASE = os.getenv("TEST_PROXY_URL", "http://localhost:8000")
API_KEY = os.getenv("API_KEY", _env.get("API_KEY", ""))
DEFAULT_USER_ID = "e2e-test-user-1"


@pytest.fixture(scope="session")
def base_url() -> str:
    return PROXY_BASE


@pytest.fixture(scope="session")
def api_key() -> str:
    assert API_KEY and API_KEY != "your-api-key-here", (
        "API_KEY not configured — run `just setup-demo` first"
    )
    return API_KEY


@pytest.fixture(scope="session")
def user_id() -> str:
    return DEFAULT_USER_ID


@pytest.fixture(scope="session")
def auth_headers(api_key: str, user_id: str) -> Dict[str, str]:
    return {
        "X-API-Key": api_key,
        "X-User-ID": user_id,
    }


@pytest.fixture(scope="session")
def client(base_url: str) -> httpx.Client:
    """Shared httpx client with generous timeout for downstream calls."""
    with httpx.Client(base_url=base_url, timeout=30.0) as c:
        yield c


# ---------------------------------------------------------------------------
# Pre-flight: make sure the proxy is reachable before running any tests
# ---------------------------------------------------------------------------

def pytest_configure(config):
    """Skip entire suite early if proxy is unreachable."""
    url = os.getenv("TEST_PROXY_URL", "http://localhost:8000")
    try:
        r = httpx.get(f"{url}/docs", timeout=5.0)
        if r.status_code >= 500:
            pytest.exit(f"Proxy at {url} returned {r.status_code} — is it healthy?")
    except httpx.ConnectError:
        pytest.exit(
            f"Cannot connect to proxy at {url}. "
            "Start services first: just start-services && just setup-demo"
        )
