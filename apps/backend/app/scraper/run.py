"""
Scraper orchestrator — upserts skills from all enabled sources into Postgres.

Usage:
    python -m app.scraper.run

Safe to run on a cron schedule; duplicate / unchanged skills are skipped.
NEVER called at API request time (AGENTS.md rule 4).

Upsert strategy:
  - Unique key: (repo, repo_path)
  - If content_hash matches the stored row → skip (no DB write).
  - Otherwise INSERT … ON CONFLICT DO UPDATE.
"""
from __future__ import annotations

import asyncio
import logging
import sys
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.config import get_settings
from app.database import async_session_factory, engine
from app.models import Base, Skill, SkillSource
from app.scraper.base import SkillRecord
from app.scraper.github import GitHubSource
from app.scraper.skills_sh import SkillsShSource

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    stream=sys.stdout,
)
logger = logging.getLogger(__name__)


async def upsert_skill(session, record: SkillRecord) -> str:
    """
    Insert or update a skill row.  Returns "inserted", "updated", or "skipped".
    """
    # Check existing row by (repo, repo_path)
    existing = (
        await session.execute(
            select(Skill).where(
                Skill.repo == record.repo,
                Skill.repo_path == record.repo_path,
            )
        )
    ).scalar_one_or_none()

    if existing is not None and existing.content_hash == record.content_hash:
        return "skipped"

    now = datetime.now(timezone.utc)

    stmt = (
        pg_insert(Skill)
        .values(
            name=record.name,
            folder_name=record.folder_name,
            description=record.description,
            tags=record.tags,
            source=SkillSource(record.source),
            source_url=record.source_url,
            repo=record.repo,
            repo_path=record.repo_path,
            commit_sha=record.commit_sha,
            skill_md=record.skill_md,
            content_hash=record.content_hash,
            created_at=now,
            updated_at=now,
        )
        .on_conflict_do_update(
            index_elements=["repo", "repo_path"],
            set_=dict(
                name=record.name,
                folder_name=record.folder_name,
                description=record.description,
                tags=record.tags,
                source_url=record.source_url,
                commit_sha=record.commit_sha,
                skill_md=record.skill_md,
                content_hash=record.content_hash,
                updated_at=now,
            ),
        )
    )
    await session.execute(stmt)
    return "inserted" if existing is None else "updated"


async def run() -> None:
    settings = get_settings()

    sources = [GitHubSource()]
    if settings.skills_sh_enabled:
        sources.append(SkillsShSource())
        logger.info("skills.sh source ENABLED (stub — no real data)")

    all_records: list[SkillRecord] = []
    for source in sources:
        logger.info("Fetching from %s …", type(source).__name__)
        records = await source.fetch_skills()
        logger.info("  → %d skills returned", len(records))
        all_records.extend(records)

    counts = {"inserted": 0, "updated": 0, "skipped": 0}
    async with async_session_factory() as session:
        for record in all_records:
            action = await upsert_skill(session, record)
            counts[action] += 1
        await session.commit()

    logger.info(
        "Scrape finished: %d inserted, %d updated, %d skipped",
        counts["inserted"],
        counts["updated"],
        counts["skipped"],
    )


if __name__ == "__main__":
    asyncio.run(run())

