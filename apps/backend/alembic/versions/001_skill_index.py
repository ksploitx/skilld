"""001 — skill index

Revision ID: 001_skill_index
Create date: 2026-11-02
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "001_skill_index"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 1. Enable pgcrypto for gen_random_uuid() (no-op if already installed)
    op.execute("CREATE EXTENSION IF NOT EXISTS pgcrypto")

    # 2. Create source enum (idempotent — PL/pgSQL handles already-exists gracefully)
    op.execute(sa.text(
        """
        DO $$ BEGIN
            CREATE TYPE skillsource AS ENUM ('github', 'skills_sh');
        EXCEPTION
            WHEN duplicate_object THEN NULL;
        END $$;
        """
    ))

    # 3. Create skills table (without the generated column first)
    op.create_table(
        "skills",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
            nullable=False,
        ),
        sa.Column("name", sa.Text, nullable=False),
        sa.Column("folder_name", sa.Text, nullable=False),
        sa.Column("description", sa.Text, nullable=True),
        sa.Column(
            "tags",
            postgresql.ARRAY(sa.Text),
            nullable=False,
            server_default="{}",
        ),
        sa.Column("skill_md", sa.Text, nullable=False),
        sa.Column("content_hash", sa.Text, nullable=False),
        sa.Column(
            "source",
            sa.Enum("github", "skills_sh", name="skillsource", create_type=False),
            nullable=False,
        ),
        sa.Column("source_url", sa.Text, nullable=False),
        sa.Column("repo", sa.Text, nullable=False),
        sa.Column("repo_path", sa.Text, nullable=False),
        sa.Column("commit_sha", sa.Text, nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
    )

    # 4. Add generated tsvector column (must be done with raw SQL; Alembic
    #    doesn't have a first-class Computed column helper for tsvector).
    op.execute(
        """
        ALTER TABLE skills ADD COLUMN search_vector TSVECTOR
        GENERATED ALWAYS AS (
            setweight(to_tsvector('pg_catalog.english'::regconfig, coalesce(name, '')), 'A') ||
            setweight(to_tsvector('pg_catalog.english'::regconfig, coalesce(description, '')), 'B') ||
            setweight(to_tsvector('pg_catalog.english'::regconfig, coalesce(skill_md, '')), 'D')
        ) STORED
        """
    )

    # 5. Indexes
    op.create_index(
        "ix_skills_search_vector",
        "skills",
        ["search_vector"],
        postgresql_using="gin",
    )
    op.create_index(
        "ix_skills_repo_path",
        "skills",
        ["repo", "repo_path"],
        unique=True,
    )
    op.create_index(
        "ix_skills_updated_at",
        "skills",
        ["updated_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_skills_updated_at", table_name="skills")
    op.drop_index("ix_skills_repo_path", table_name="skills")
    op.drop_index("ix_skills_search_vector", table_name="skills")
    op.drop_table("skills")
    op.execute("DROP TYPE IF EXISTS skillsource")

