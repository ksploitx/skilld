"""
Abstract base class that every source adapter must implement.
"""
from __future__ import annotations

import abc
from dataclasses import dataclass, field
from datetime import datetime, timezone


@dataclass
class SkillRecord:
    """
    Normalised skill record produced by a source adapter.
    All fields map 1-to-1 onto the Skill ORM model.
    """

    name: str
    folder_name: str
    description: str | None
    tags: list[str]
    source: str                # "github" | "skills_sh"
    source_url: str            # canonical human-readable URL
    repo: str                  # "owner/repo"
    repo_path: str             # path inside repo, e.g. ".claude/skills/git-commit"
    commit_sha: str            # pinned commit SHA
    skill_md: str              # full raw SKILL.md text
    content_hash: str          # SHA-256 of skill_md
    scraped_at: datetime = field(
        default_factory=lambda: datetime.now(timezone.utc)
    )


class BaseSource(abc.ABC):
    """Source adapter interface."""

    @abc.abstractmethod
    async def fetch_skills(self) -> list[SkillRecord]:
        """
        Fetch all skills from this source.
        Must not make live requests at API-request time (AGENTS.md rule 4).
        Must handle its own rate-limiting and pagination.
        """
        ...

