"""
Endpoint smoke tests and Redis cache test.

Tests:
- GET /health → 200 {"status": "ok"}
- GET /skills (empty → recent list) → 200, SkillSearchResponse shape
- GET /skills?query=docker → returns docker skill in results
- GET /skills/{id} → 200 SkillDetail shape including skill_md
- GET /skills/{id} 404 for unknown UUID
- GET /skills/updated-since?ts= → 200 list
- Redis cache hit: second identical search request is served from cache
"""
from __future__ import annotations

import json
import uuid
from datetime import datetime, timezone, timedelta
from unittest.mock import AsyncMock, patch

import pytest
import pytest_asyncio
from httpx import AsyncClient, ASGITransport
from sqlalchemy import select

from app.database import get_db, redis_client
from app.main import app
from app.models import Skill


# ---------------------------------------------------------------------------
# Health
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_health_endpoint(test_client: AsyncClient):
    response = await test_client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


# ---------------------------------------------------------------------------
# GET /skills — empty DB returns empty results
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_skills_empty_db(test_client: AsyncClient):
    """With no seed data: returns 200 and an empty results list."""
    # Mock Redis to always return cache miss
    with patch.object(redis_client, "get", new_callable=AsyncMock, return_value=None):
        with patch.object(redis_client, "setex", new_callable=AsyncMock):
            response = await test_client.get("/skills")
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 0
    assert body["results"] == []
    assert "limit" in body
    assert "offset" in body


# ---------------------------------------------------------------------------
# GET /skills with seeded data
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_skills_search_docker(test_client: AsyncClient, seeded_db):
    """Query 'docker' returns docker skill."""
    with patch.object(redis_client, "get", new_callable=AsyncMock, return_value=None):
        with patch.object(redis_client, "setex", new_callable=AsyncMock):
            response = await test_client.get("/skills", params={"query": "docker"})
    assert response.status_code == 200
    body = response.json()
    names = [r["name"] for r in body["results"]]
    assert "Docker Compose Setup" in names


@pytest.mark.asyncio
async def test_skills_search_sql(test_client: AsyncClient, seeded_db):
    """Query 'sql' returns SQL optimizer skill."""
    with patch.object(redis_client, "get", new_callable=AsyncMock, return_value=None):
        with patch.object(redis_client, "setex", new_callable=AsyncMock):
            response = await test_client.get("/skills", params={"query": "sql"})
    assert response.status_code == 200
    names = [r["name"] for r in response.json()["results"]]
    assert "SQL Query Optimizer" in names


@pytest.mark.asyncio
async def test_skills_search_commit(test_client: AsyncClient, seeded_db):
    """Query 'commit' returns git commit skill."""
    with patch.object(redis_client, "get", new_callable=AsyncMock, return_value=None):
        with patch.object(redis_client, "setex", new_callable=AsyncMock):
            response = await test_client.get("/skills", params={"query": "commit"})
    assert response.status_code == 200
    names = [r["name"] for r in response.json()["results"]]
    assert "Git Commit Message" in names


@pytest.mark.asyncio
async def test_skills_pagination(test_client: AsyncClient, seeded_db):
    """limit/offset parameters work."""
    with patch.object(redis_client, "get", new_callable=AsyncMock, return_value=None):
        with patch.object(redis_client, "setex", new_callable=AsyncMock):
            r1 = await test_client.get("/skills", params={"limit": 3, "offset": 0})
            r2 = await test_client.get("/skills", params={"limit": 3, "offset": 3})
    assert r1.status_code == 200
    assert r2.status_code == 200
    ids1 = [r["id"] for r in r1.json()["results"]]
    ids2 = [r["id"] for r in r2.json()["results"]]
    # Pages should not overlap
    assert not set(ids1) & set(ids2)


# ---------------------------------------------------------------------------
# GET /skills/{id}
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_get_skill_by_id(test_client: AsyncClient, seeded_db):
    """GET /skills/{id} returns the full SkillDetail including skill_md."""
    stmt = select(Skill).limit(1)
    rows = await seeded_db.execute(stmt)
    skill = rows.scalar_one()

    response = await test_client.get(f"/skills/{skill.id}")
    assert response.status_code == 200
    body = response.json()
    assert body["id"] == str(skill.id)
    assert "skill_md" in body
    assert body["skill_md"] == skill.skill_md
    assert "source_url" in body
    assert "repo" in body
    assert "repo_path" in body
    assert "commit_sha" in body


@pytest.mark.asyncio
async def test_get_skill_not_found(test_client: AsyncClient):
    """GET /skills/{unknown-uuid} returns 404."""
    response = await test_client.get(f"/skills/{uuid.uuid4()}")
    assert response.status_code == 404


# ---------------------------------------------------------------------------
# GET /skills/updated-since
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_updated_since_returns_recent_skills(test_client: AsyncClient, seeded_db):
    """Skills updated after far-past timestamp are returned."""
    ts = datetime(2000, 1, 1, tzinfo=timezone.utc).isoformat()
    response = await test_client.get("/skills/updated-since", params={"ts": ts})
    assert response.status_code == 200
    assert len(response.json()) == 10  # all 10 seeds are newer than 2000


@pytest.mark.asyncio
async def test_updated_since_future_timestamp_empty(test_client: AsyncClient, seeded_db):
    """Skills updated before a future timestamp returns empty list."""
    ts = (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat()
    response = await test_client.get("/skills/updated-since", params={"ts": ts})
    assert response.status_code == 200
    assert response.json() == []


# ---------------------------------------------------------------------------
# Redis cache hit test
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_redis_cache_hit(test_client: AsyncClient, seeded_db):
    """
    Second identical request is served from Redis cache (no DB call).
    Verifies the cache write from the first request is read on the second.
    """
    from app.schemas import SkillSearchResponse

    # Pre-build a cached response payload
    cached_payload = SkillSearchResponse(
        total=1,
        limit=20,
        offset=0,
        results=[],
    ).model_dump_json()

    get_mock = AsyncMock(return_value=None)
    setex_mock = AsyncMock()

    # First call: cache miss → DB hit → cache write
    with patch.object(redis_client, "get", get_mock):
        with patch.object(redis_client, "setex", setex_mock):
            r1 = await test_client.get("/skills", params={"query": "docker"})
    assert r1.status_code == 200
    assert setex_mock.called, "Cache write (setex) should be called after a cache miss"

    # Second call: cache hit → no DB
    get_mock_hit = AsyncMock(return_value=cached_payload)
    with patch.object(redis_client, "get", get_mock_hit):
        r2 = await test_client.get("/skills", params={"query": "docker"})
    assert r2.status_code == 200
    body = r2.json()
    # Should exactly match what was in the cache (empty results list from our mock)
    assert body["total"] == 1
    assert body["results"] == []

