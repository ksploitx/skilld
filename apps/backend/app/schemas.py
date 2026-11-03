"""
Pydantic response models for the Skills API.

These must stay field-for-field in sync with the TypeScript interfaces in
packages/shared-types/src/index.ts.  When adding a field here, add it there
too (and vice-versa).
"""
from __future__ import annotations

import uuid
from datetime import datetime
from enum import Enum

from pydantic import BaseModel, ConfigDict


class SkillSource(str, Enum):
    github = "github"
    skills_sh = "skills_sh"


class SkillBase(BaseModel):
    """Fields common to all skill responses."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    folder_name: str
    description: str | None
    tags: list[str]
    source: SkillSource
    source_url: str
    repo: str
    repo_path: str
    commit_sha: str
    created_at: datetime
    updated_at: datetime


class SkillSummary(SkillBase):
    """Returned in list/search results (no skill_md body to keep payload small)."""

    pass


class SkillDetail(SkillBase):
    """Returned by GET /skills/{id} — includes the full SKILL.md text."""

    skill_md: str


class SkillSearchResponse(BaseModel):
    """Envelope for paginated search results."""

    total: int
    limit: int
    offset: int
    results: list[SkillSummary]

