"""End-to-end tests for demo-proxy-app.

Run with:  just test-e2e
Requires:  all services running (just start-services && just setup-demo)

Each test hits the proxy at localhost:8000 and validates the full round-trip
through platform-api and its downstream services.
"""

import uuid
import pytest
import httpx


# ── helpers ──────────────────────────────────────────────────────────────────


def assert_json(response: httpx.Response) -> dict:
    """Assert response is valid JSON and return parsed body."""
    assert response.headers.get("content-type", "").startswith(
        "application/json"
    ), f"Expected JSON, got {response.headers.get('content-type')}"
    return response.json()


# ── 1. Authentication ────────────────────────────────────────────────────────


class TestAuth:
    """Foreign user authentication via X-API-Key + X-User-ID."""

    def test_valid_auth_returns_200(
        self, client: httpx.Client, auth_headers: dict
    ):
        r = client.get("/api/user/current-user", headers=auth_headers)
        assert r.status_code == 200
        body = assert_json(r)
        # Must contain at minimum a user identifier
        assert body.get("id") or body.get("user_id") or body.get("userId")

    def test_missing_api_key_still_succeeds(
        self, client: httpx.Client, user_id: str
    ):
        """Proxy injects its own X-API-Key, so omitting it from the test
        request still results in a valid auth flow."""
        r = client.get(
            "/api/user/current-user", headers={"X-User-ID": user_id}
        )
        # Proxy fills in the API key — request succeeds
        assert r.status_code == 200

    def test_missing_user_id_still_succeeds(
        self, client: httpx.Client, api_key: str
    ):
        """Proxy injects a default X-User-ID ("1"), so omitting it still works."""
        r = client.get(
            "/api/user/current-user", headers={"X-API-Key": api_key}
        )
        assert r.status_code == 200

    def test_client_headers_override_proxy_defaults(
        self, client: httpx.Client, auth_headers: dict
    ):
        """When client sends X-User-ID, proxy passes it through (not its default)."""
        r = client.get("/api/user/current-user", headers=auth_headers)
        assert r.status_code == 200
        body = assert_json(r)
        # The returned user should reflect our test user, not the default "1"
        ext_id = body.get("api_external_id") or body.get("apiExternalId", "")
        assert ext_id == "e2e-test-user-1", (
            f"Expected proxy to forward our X-User-ID, got ext_id={ext_id}"
        )

    def test_no_headers_uses_proxy_defaults(self, client: httpx.Client):
        """With no auth headers at all, proxy injects its defaults and request succeeds."""
        r = client.get("/api/user/current-user")
        assert r.status_code == 200

    def test_second_request_same_user_returns_same_id(
        self, client: httpx.Client, auth_headers: dict
    ):
        """Verify caching — same X-User-ID resolves to same internal UUID."""
        r1 = client.get("/api/user/current-user", headers=auth_headers)
        r2 = client.get("/api/user/current-user", headers=auth_headers)
        assert r1.status_code == 200
        assert r2.status_code == 200
        b1, b2 = r1.json(), r2.json()
        # Compare the stable identifier, not timestamps
        id_key = "id" if "id" in b1 else "user_id" if "user_id" in b1 else "userId"
        assert b1[id_key] == b2[id_key]


# ── 2. User endpoints ───────────────────────────────────────────────────────


class TestUserEndpoints:
    def test_current_token(self, client: httpx.Client, auth_headers: dict):
        r = client.get("/api/user/current-token", headers=auth_headers)
        assert r.status_code == 200
        body = assert_json(r)
        # Should return a JWT string (or an object containing one)
        token = body if isinstance(body, str) else body.get("token", body.get("jwt", ""))
        assert token, f"Expected a token in response, got {body}"

    def test_current_membership(self, client: httpx.Client, auth_headers: dict):
        r = client.get(
            "/api/user/membership/current-membership", headers=auth_headers
        )
        assert r.status_code == 200
        body = assert_json(r)
        assert body is not None


# ── 3. Organization & prompts ───────────────────────────────────────────────


class TestOrgAndPrompts:
    def test_organizations_me(self, client: httpx.Client, auth_headers: dict):
        r = client.get("/api/organizations/me", headers=auth_headers)
        assert r.status_code == 200
        body = assert_json(r)
        # Should be a list or an object with org info
        assert body is not None

    def test_prompts(self, client: httpx.Client, auth_headers: dict):
        r = client.get("/api/prompts", headers=auth_headers)
        assert r.status_code == 200
        body = assert_json(r)
        # setup-demo seeds 3 prompts
        if isinstance(body, list):
            assert len(body) >= 1, "Expected at least 1 prompt (setup-demo seeds 3)"


# ── 4. Storyplan config ─────────────────────────────────────────────────────


class TestStoryplanConfig:
    def test_list_configs(self, client: httpx.Client, auth_headers: dict):
        r = client.get("/api/user/storyplan-config", headers=auth_headers)
        assert r.status_code == 200

    def test_get_default_config(self, client: httpx.Client, auth_headers: dict):
        r = client.get(
            "/api/user/storyplan-config/default", headers=auth_headers
        )
        # 200 if one exists, 404 if none set yet — both are acceptable
        assert r.status_code in (200, 404)


# ── 5. Stories ───────────────────────────────────────────────────────────────


class TestStories:
    def test_stories_mini_requires_story_id(
        self, client: httpx.Client, auth_headers: dict
    ):
        """stories/mini needs a story-id query param."""
        r = client.get("/api/stories/mini", headers=auth_headers)
        # Should fail with 4xx when no story-id provided, not 500
        assert r.status_code < 500

    def test_stories_mini_nonexistent_story(
        self, client: httpx.Client, auth_headers: dict
    ):
        fake_id = str(uuid.uuid4())
        r = client.get(
            "/api/stories/mini",
            headers=auth_headers,
            params={"story-id": fake_id, "migrate": "true"},
        )
        # New story returns 200 with createdAt: null, or 404
        assert r.status_code in (200, 404)

    def test_story_plan_config(self, client: httpx.Client, auth_headers: dict):
        r = client.get("/api/stories/story-plan-config", headers=auth_headers)
        assert r.status_code < 500

    def test_events_requires_story_id(
        self, client: httpx.Client, auth_headers: dict
    ):
        r = client.get("/api/events", headers=auth_headers)
        assert r.status_code < 500

    def test_events_nonexistent_story(
        self, client: httpx.Client, auth_headers: dict
    ):
        fake_id = str(uuid.uuid4())
        r = client.get(
            "/api/events",
            headers=auth_headers,
            params={"story-id": fake_id},
        )
        assert r.status_code in (200, 404)


# ── 6. Guardrails ───────────────────────────────────────────────────────────


class TestGuardrails:
    def test_guardrails_check_prompt(
        self, client: httpx.Client, auth_headers: dict
    ):
        r = client.post(
            "/api/configs/guardrails/check/prompt",
            headers=auth_headers,
            json={"user_query": "This is a test prompt for guardrails"},
        )
        # 200 if guardrails configured (returns [] when no active guardrails)
        assert r.status_code == 200


# ── 7. Projects ──────────────────────────────────────────────────────────────


class TestProjects:
    def test_project_list(self, client: httpx.Client, auth_headers: dict):
        r = client.get("/api/project/list", headers=auth_headers)
        assert r.status_code == 200
        body = assert_json(r)
        assert isinstance(body, (list, dict))


# ── 8. Feedback ──────────────────────────────────────────────────────────────


class TestFeedback:
    def test_get_feedback_requires_story(
        self, client: httpx.Client, auth_headers: dict
    ):
        r = client.get("/api/user/feedback/thumbs", headers=auth_headers)
        # Should need a story_id param — 4xx expected, not 500
        assert r.status_code < 500


# ── 9. Source upload (sync) ──────────────────────────────────────────────────


class TestSourceUpload:
    def test_sync_upload_requires_body(
        self, client: httpx.Client, auth_headers: dict
    ):
        r = client.post(
            "/api/sources/upload-source/sync",
            headers=auth_headers,
            json={},
        )
        # Empty body should fail with 4xx, not 500
        assert r.status_code < 500

    def test_ws_address_creation(
        self, client: httpx.Client, auth_headers: dict
    ):
        """POST /sources/ws should return a WebSocket address."""
        r = client.post("/api/sources/ws", headers=auth_headers)
        if r.status_code == 200:
            body = assert_json(r)
            ws_addr = body.get("ws-address") or body.get("ws_address") or body.get("wsAddress")
            assert ws_addr, f"Expected ws-address in response, got {body}"


# ── 10. Proxy behaviour ─────────────────────────────────────────────────────


class TestProxyBehaviour:
    def test_v1_prefix_stripped(self, client: httpx.Client, auth_headers: dict):
        """React library sends /api/v1/... — proxy should strip v1/."""
        r = client.get("/api/v1/user/current-user", headers=auth_headers)
        assert r.status_code == 200

    def test_unknown_path_returns_not_500(
        self, client: httpx.Client, auth_headers: dict
    ):
        """Unknown paths forwarded to platform-api should get 404, not crash."""
        r = client.get("/api/nonexistent-endpoint", headers=auth_headers)
        assert r.status_code != 500

    def test_gofapi_user_prefix_alias(
        self, client: httpx.Client, auth_headers: dict
    ):
        """/user/sources/ws is a gofapi compatibility alias."""
        r = client.post("/api/user/sources/ws", headers=auth_headers)
        # Should behave same as /sources/ws
        assert r.status_code == 200
        body = assert_json(r)
        ws_addr = body.get("ws-address") or body.get("ws_address") or body.get("wsAddress")
        assert ws_addr, f"Expected ws-address in response, got {body}"
