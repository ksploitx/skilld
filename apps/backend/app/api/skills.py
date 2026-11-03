"""
Skills API router.

Endpoints:
  GET /skills?query=&tags=&limit=&offset=
  GET /skills/updated-since?ts=
  GET /skills/{id}

Cache strategy:
  - Search results are cached in Redis for SEARCH_CACHE_TTL_SECONDS (60s).
  - The cache key encodes query + tags + limit + offset.
  - Cache is safe to flush at any time (it's a read-only hot-path cache).
  - The search endpoint NEVER triggers a scrape (AGENTS.md rule 4).
"""
from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.database import get_db, redis_client
from app.models import Skill
from app.schemas import SkillDetail, SkillSearchResponse, SkillSummary

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/skills", tags=["skills"])

_settings = get_settings()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _cache_key(query: str, tags: list[str], limit: int, offset: int) -> str:
    tag_part = ",".join(sorted(tags))
    return f"search:{query}:{tag_part}:{limit}:{offset}"


def _skill_summary_dict(skill: Skill) -> dict:
    """Serialize a Skill ORM row to a JSON-safe dict (no skill_md)."""
    return {
        "id": str(skill.id),
        "name": skill.name,
        "folder_name": skill.folder_name,
        "description": skill.description,
        "tags": skill.tags or [],
        "source": skill.source.value,
        "source_url": skill.source_url,
        "repo": skill.repo,
        "repo_path": skill.repo_path,
        "commit_sha": skill.commit_sha,
        "created_at": skill.created_at.isoformat(),
        "updated_at": skill.updated_at.isoformat(),
    }


# ---------------------------------------------------------------------------
# GET /skills  — search / list
# ---------------------------------------------------------------------------

@router.get("", response_model=SkillSearchResponse)
async def search_skills(
    query: Annotated[str, Query(description="Full-text search query")] = "",
    tags: Annotated[
        list[str], Query(description="Filter by one or more tags")
    ] = [],
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
    db: AsyncSession = Depends(get_db),
) -> SkillSearchResponse:
    """
    Search skills using Postgres full-text search (ts_rank).
    An empty query returns the most recently updated skills.
    Results are cached in Redis for 60 s.
    This endpoint NEVER triggers a live scrape.
    """
    cache_key = _cache_key(query, tags, limit, offset)

    # ── Cache read ────────────────────────────────────────────────────────
    try:
        cached = await redis_client.get(cache_key)
        if cached:
            return SkillSearchResponse(**json.loads(cached))
    except Exception:
        logger.warning("Redis read failed — serving from DB", exc_info=True)

    # ── Build query ───────────────────────────────────────────────────────
    stmt = select(Skill)

    if tags:
        # Filter: skill must contain ALL requested tags (overlap: use &&)
        stmt = stmt.where(Skill.tags.overlap(tags))  # type: ignore[attr-defined]

    if query:
        tsquery = func.plainto_tsquery("english", query)
        stmt = (
            stmt.where(Skill.search_vector.op("@@")(tsquery))
            .order_by(func.ts_rank(Skill.search_vector, tsquery).desc())
        )
    else:
        stmt = stmt.order_by(Skill.updated_at.desc())

    # Total count (same filters, no limit/offset)
    count_stmt = select(func.count()).select_from(stmt.subquery())
    total_result = await db.execute(count_stmt)
    total = total_result.scalar_one()

    # Paginated rows
    paginated = stmt.limit(limit).offset(offset)
    rows = await db.execute(paginated)
    skills = rows.scalars().all()

    response = SkillSearchResponse(
        total=total,
        limit=limit,
        offset=offset,
        results=[SkillSummary.model_validate(s) for s in skills],
    )

    # ── Cache write ───────────────────────────────────────────────────────
    try:
        await redis_client.setex(
            cache_key,
            _settings.search_cache_ttl_seconds,
            response.model_dump_json(),
        )
    except Exception:
        logger.warning("Redis write failed — response not cached", exc_info=True)

    return response


# ---------------------------------------------------------------------------
# GET /skills/updated-since  — must be declared BEFORE /{id} to avoid clash
# ---------------------------------------------------------------------------

@router.get("/updated-since", response_model=list[SkillSummary])
async def skills_updated_since(
    ts: Annotated[
        datetime,
        Query(description="ISO 8601 timestamp; returns skills updated after this time"),
    ],
    db: AsyncSession = Depends(get_db),
) -> list[SkillSummary]:
    """
    Return skills updated after *ts*.
    Used by the menubar app to check whether any installed skills have
    upstream updates without re-fetching the full catalogue.
    """
    # Ensure ts is timezone-aware for comparison with UTC timestamps
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=timezone.utc)

    stmt = select(Skill).where(Skill.updated_at > ts).order_by(Skill.updated_at.desc())
    rows = await db.execute(stmt)
    skills = rows.scalars().all()
    return [SkillSummary.model_validate(s) for s in skills]


# ---------------------------------------------------------------------------
# GET /skills/{id}
# ---------------------------------------------------------------------------

@router.get("/{skill_id}", response_model=SkillDetail)
async def get_skill(
    skill_id: UUID,
    db: AsyncSession = Depends(get_db),
) -> SkillDetail:
    """Return a single skill including its full SKILL.md content."""
    result = await db.execute(select(Skill).where(Skill.id == skill_id))
    skill = result.scalar_one_or_none()
    if skill is None:
        raise HTTPException(status_code=404, detail="Skill not found")
    return SkillDetail.model_validate(skill)

