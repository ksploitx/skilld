"""
SQLAlchemy ORM model for the Skill table.

Key design decisions:
- UUID primary key (server default via gen_random_uuid()).
- tags stored as Postgres ARRAY(Text).
- skill_md stores the raw SKILL.md text for full-text search only.
  The full folder is fetched from GitHub at install time using
  repo + repo_path + commit_sha.
- search_vector is a generated tsvector column (Postgres 12+) over
  name, description, array_to_string(tags) and skill_md, indexed
  with a GIN index for fast full-text search.
- content_hash (SHA-256 of skill_md) lets the scraper skip unchanged skills.
- source enum matches the TS SkillSource type in packages/shared-types.
"""
import enum
import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    ARRAY,
    Column,
    DateTime,
    Enum,
    Index,
    Text,
    Computed,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.types import UserDefinedType

from app.database import Base


class TSVector(UserDefinedType):
    """Thin SQLAlchemy type wrapper for Postgres tsvector."""

    cache_ok = True

    def get_col_spec(self, **kw):  # noqa: ARG002
        return "TSVECTOR"


class SkillSource(str, enum.Enum):
    github = "github"
    skills_sh = "skills_sh"


class Skill(Base):
    __tablename__ = "skills"

    # ── identity ────────────────────────────────────────────────────────────
    id = Column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default="gen_random_uuid()",
    )

    # ── content fields ───────────────────────────────────────────────────────
    name = Column(Text, nullable=False)
    folder_name = Column(Text, nullable=False)          # e.g. "git-commit"
    description = Column(Text, nullable=True)
    tags = Column(ARRAY(Text), nullable=False, default=list)
    skill_md = Column(Text, nullable=False)             # raw SKILL.md (search only)
    content_hash = Column(Text, nullable=False)         # SHA-256 of skill_md

    # ── provenance ───────────────────────────────────────────────────────────
    source = Column(Enum(SkillSource), nullable=False)
    source_url = Column(Text, nullable=False)           # canonical human URL
    repo = Column(Text, nullable=False)                 # "owner/repo"
    repo_path = Column(Text, nullable=False)            # path inside repo
    commit_sha = Column(Text, nullable=False)           # pinned commit

    # ── timestamps ───────────────────────────────────────────────────────────
    created_at = Column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
    )
    updated_at = Column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )

    # ── full-text search vector ───────────────────────────────────────────────
    # Generated column: Postgres maintains it automatically on INSERT/UPDATE.
    # Expression combines name (weight A), description (B), tags (C), skill_md (D).
    search_vector = Column(
        TSVector,
        Computed(
            """
            setweight(to_tsvector('english', coalesce(name, '')), 'A') ||
            setweight(to_tsvector('english', coalesce(description, '')), 'B') ||
            setweight(to_tsvector('english', coalesce(array_to_string(tags, ' '), '')), 'C') ||
            setweight(to_tsvector('english', coalesce(skill_md, '')), 'D')
            """,
            persisted=True,
        ),
        nullable=False,
    )

    # ── indexes ───────────────────────────────────────────────────────────────
    __table_args__ = (
        # GIN index on the generated tsvector for fast full-text search.
        Index("ix_skills_search_vector", "search_vector", postgresql_using="gin"),
        # Unique constraint used by the scraper's upsert-by-provenance logic.
        Index("ix_skills_repo_path", "repo", "repo_path", unique=True),
    )

    def __repr__(self) -> str:
        return f"<Skill id={self.id} name={self.name!r} source={self.source}>"

