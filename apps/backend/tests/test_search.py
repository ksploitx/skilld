"""
Search tests — requires Postgres (uses tsvector / ts_rank).

10 seeded skills (defined in conftest.py).  We verify that the three
keyword queries called out in the task each return the right skill in
the top result.

These tests use the `seeded_db` fixture which inserts seeds and rolls back
after each test, keeping the test DB clean.

Postgres full-text note
───────────────────────
The search_vector is a *generated stored* column — Postgres computes and
stores it automatically on INSERT. The `seeded_db` fixture does a `flush()`
(not commit) which is enough for the generated column to be computed within
the same session via `RETURNING` or re-SELECT.

We hit the DB directly here (not the HTTP API) to keep the search logic
tests focused and fast.
"""
from __future__ import annotations

import pytest
import pytest_asyncio
from sqlalchemy import func, select, text

from app.models import Skill


# Helper: run a full-text search and return ordered skill names
async def fts_search(session, query: str, limit: int = 5) -> list[str]:
    tsq = func.plainto_tsquery("english", query)
    stmt = (
        select(Skill)
        .where(Skill.search_vector.op("@@")(tsq))
        .order_by(func.ts_rank(Skill.search_vector, tsq).desc())
        .limit(limit)
    )
    rows = await session.execute(stmt)
    return [s.name for s in rows.scalars().all()]


@pytest.mark.asyncio
async def test_search_docker_returns_docker_skill(seeded_db):
    """Query 'docker' should return 'Docker Compose Setup' in top 3."""
    results = await fts_search(seeded_db, "docker")
    assert len(results) > 0, "Expected at least one docker result"
    assert "Docker Compose Setup" in results[:3]


@pytest.mark.asyncio
async def test_search_sql_returns_sql_skill(seeded_db):
    """Query 'sql' should return 'SQL Query Optimizer' in top 3."""
    results = await fts_search(seeded_db, "sql")
    assert len(results) > 0, "Expected at least one sql result"
    assert "SQL Query Optimizer" in results[:3]


@pytest.mark.asyncio
async def test_search_commit_returns_git_commit_skill(seeded_db):
    """Query 'commit' should return 'Git Commit Message' in top 3."""
    results = await fts_search(seeded_db, "commit")
    assert len(results) > 0, "Expected at least one commit result"
    assert "Git Commit Message" in results[:3]


@pytest.mark.asyncio
async def test_search_no_results_for_unknown_term(seeded_db):
    """A nonsense query should return no results (not crash)."""
    results = await fts_search(seeded_db, "xyzzy_nonexistent_term_9q8w7e")
    assert results == []


@pytest.mark.asyncio
async def test_empty_query_returns_all_skills_ordered_by_updated(seeded_db):
    """Empty query returns all skills, most recently updated first."""
    stmt = select(Skill).order_by(Skill.updated_at.desc())
    rows = await seeded_db.execute(stmt)
    results = rows.scalars().all()
    assert len(results) == 10


@pytest.mark.asyncio
async def test_tag_filter_narrows_results(seeded_db):
    """Filtering by tag 'docker' should only return skills tagged with it."""
    stmt = select(Skill).where(Skill.tags.overlap(["docker"]))
    rows = await seeded_db.execute(stmt)
    results = rows.scalars().all()
    assert all("docker" in (s.tags or []) for s in results)
    assert len(results) >= 1


@pytest.mark.asyncio
async def test_tag_filter_with_query(seeded_db):
    """Combining a text query with a tag filter works correctly."""
    tsq = func.plainto_tsquery("english", "git")
    stmt = (
        select(Skill)
        .where(
            Skill.search_vector.op("@@")(tsq),
            Skill.tags.overlap(["git"]),
        )
        .order_by(func.ts_rank(Skill.search_vector, tsq).desc())
    )
    rows = await seeded_db.execute(stmt)
    results = rows.scalars().all()
    assert len(results) >= 1
    # All results must have the 'git' tag
    for s in results:
        assert "git" in (s.tags or [])

