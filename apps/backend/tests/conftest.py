"""
Shared pytest fixtures for the backend test suite.

Database strategy
─────────────────
Full-text search (tsvector, ts_rank, GIN index) is Postgres-specific and
cannot be replicated with SQLite.  Tests that exercise search therefore need
a real Postgres instance.

We use two fixture tiers:

1. `db_engine` / `db_session` — spins up against a real Postgres test
   database (DATABASE_URL env var, defaulting to the same host as dev but
   database name "skilld_test").  Skipped automatically if Postgres is not
   reachable (CI without Postgres, offline dev).

2. For scraper unit tests we use a plain in-memory dict and mock everything
   at the HTTP client level — no DB needed.

The FastAPI TestClient fixtures also use the real-Postgres session when
a DB is available, or an in-memory SQLite-backed app for pure smoke tests
(endpoints that don't touch DB).

Environment variable:
  TEST_DATABASE_URL — overrides the Postgres URL used in tests.
                      Defaults to the DATABASE_URL env with database
                      changed to "skilld_test".
"""
from __future__ import annotations

import asyncio
import os
import re
import uuid
from datetime import datetime, timezone

import pytest
import pytest_asyncio
from httpx import AsyncClient, ASGITransport
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.database import Base, get_db, redis_client
from app.main import app
from app.models import Skill, SkillSource


# ---------------------------------------------------------------------------
# Test DB URL — replace database name to isolate from dev data
# ---------------------------------------------------------------------------

def _test_db_url() -> str:
    base = os.getenv(
        "TEST_DATABASE_URL",
        os.getenv(
            "DATABASE_URL",
            "postgresql+asyncpg://postgres:postgres@localhost:5432/skilld",
        ),
    )
    # Replace the database name with "skilld_test"
    return re.sub(r"/[^/]+$", "/skilld_test", base)


TEST_DB_URL = _test_db_url()


# ---------------------------------------------------------------------------
# Postgres availability probe
# ---------------------------------------------------------------------------

async def _postgres_available(url: str) -> bool:
    try:
        engine = create_async_engine(url, pool_pre_ping=True)
        async with engine.connect() as conn:
            await conn.execute(__import__("sqlalchemy").text("SELECT 1"))
        await engine.dispose()
        return True
    except Exception:
        return False


@pytest.fixture(scope="session")
def postgres_available() -> bool:
    return asyncio.get_event_loop().run_until_complete(
        _postgres_available(TEST_DB_URL)
    )


# ---------------------------------------------------------------------------
# Session-scoped engine + per-test transactional session
# ---------------------------------------------------------------------------

@pytest_asyncio.fixture(scope="session")
async def db_engine(postgres_available):
    if not postgres_available:
        pytest.skip("Postgres not reachable — skipping DB-backed tests")
    engine = create_async_engine(TEST_DB_URL, echo=False)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    yield engine
    await engine.dispose()


@pytest_asyncio.fixture
async def db_session(db_engine) -> AsyncSession:
    """Each test gets its own session; changes are rolled back after."""
    factory = async_sessionmaker(db_engine, class_=AsyncSession, expire_on_commit=False)
    async with factory() as session:
        yield session
        await session.rollback()


# ---------------------------------------------------------------------------
# FastAPI test client wired to the test DB
# ---------------------------------------------------------------------------

@pytest_asyncio.fixture
async def test_client(db_session: AsyncSession) -> AsyncClient:
    """HTTPX async client pointed at the test FastAPI app."""
    async def override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        yield client
    app.dependency_overrides.clear()


# ---------------------------------------------------------------------------
# 10 seed skills for search tests
# ---------------------------------------------------------------------------

SEED_SKILLS = [
    {
        "name": "Docker Compose Setup",
        "folder_name": "docker-compose-setup",
        "description": "Generates a docker-compose.yml for the current project with postgres and redis services.",
        "tags": ["docker", "devops", "compose"],
        "skill_md": "---\nname: Docker Compose Setup\ndescription: Generates a docker-compose.yml\ntags: [docker, devops, compose]\n---\nRun docker-compose up -d.",
        "content_hash": "hash-docker",
        "source": SkillSource.github,
        "source_url": "https://github.com/example/skills/docker-compose-setup",
        "repo": "example/skills",
        "repo_path": ".claude/skills/docker-compose-setup",
        "commit_sha": "abc0001",
    },
    {
        "name": "SQL Query Optimizer",
        "folder_name": "sql-optimizer",
        "description": "Analyzes slow SQL queries and rewrites them with proper indexes and query hints.",
        "tags": ["sql", "database", "performance"],
        "skill_md": "---\nname: SQL Query Optimizer\ndescription: Analyzes slow SQL queries.\ntags: [sql, database]\n---\nREWRITE slow queries.",
        "content_hash": "hash-sql",
        "source": SkillSource.github,
        "source_url": "https://github.com/example/skills/sql-optimizer",
        "repo": "example/skills",
        "repo_path": ".claude/skills/sql-optimizer",
        "commit_sha": "abc0002",
    },
    {
        "name": "Git Commit Message",
        "folder_name": "git-commit",
        "description": "Writes a conventional commit message from staged diff output.",
        "tags": ["git", "commit", "conventional-commits"],
        "skill_md": "---\nname: Git Commit Message\ndescription: Writes a conventional commit message.\ntags: [git, commit]\n---\nGenerate commit message from diff.",
        "content_hash": "hash-git-commit",
        "source": SkillSource.github,
        "source_url": "https://github.com/example/skills/git-commit",
        "repo": "example/skills",
        "repo_path": ".claude/skills/git-commit",
        "commit_sha": "abc0003",
    },
    {
        "name": "Python Expert",
        "folder_name": "python-expert",
        "description": "Enables expert-level Python code review mode.",
        "tags": ["python", "code-review"],
        "skill_md": "---\nname: Python Expert\ndescription: Expert Python code review.\ntags: [python]\n---\nReview Python code.",
        "content_hash": "hash-python",
        "source": SkillSource.github,
        "source_url": "https://github.com/example/skills/python-expert",
        "repo": "example/skills",
        "repo_path": ".claude/skills/python-expert",
        "commit_sha": "abc0004",
    },
    {
        "name": "Code Review Checklist",
        "folder_name": "code-review",
        "description": "Runs a structured code review checklist covering security, performance and style.",
        "tags": ["code-review", "security", "quality"],
        "skill_md": "---\nname: Code Review Checklist\ndescription: Structured code review.\ntags: [code-review, security]\n---\nRun review checklist.",
        "content_hash": "hash-review",
        "source": SkillSource.github,
        "source_url": "https://github.com/example/skills/code-review",
        "repo": "example/skills",
        "repo_path": ".claude/skills/code-review",
        "commit_sha": "abc0005",
    },
    {
        "name": "API Conventions",
        "folder_name": "api-conventions",
        "description": "Enforces REST API naming conventions and OpenAPI schema best practices.",
        "tags": ["api", "rest", "openapi"],
        "skill_md": "---\nname: API Conventions\ndescription: REST API naming conventions.\ntags: [api, rest]\n---\nCheck API conventions.",
        "content_hash": "hash-api",
        "source": SkillSource.github,
        "source_url": "https://github.com/example/skills/api-conventions",
        "repo": "example/skills",
        "repo_path": ".claude/skills/api-conventions",
        "commit_sha": "abc0006",
    },
    {
        "name": "Terraform Plan",
        "folder_name": "terraform-plan",
        "description": "Runs terraform plan and summarises changes in plain English.",
        "tags": ["terraform", "devops", "infrastructure"],
        "skill_md": "---\nname: Terraform Plan\ndescription: Summarise terraform plan.\ntags: [terraform, devops]\n---\nRun terraform plan.",
        "content_hash": "hash-terraform",
        "source": SkillSource.github,
        "source_url": "https://github.com/example/skills/terraform-plan",
        "repo": "example/skills",
        "repo_path": ".claude/skills/terraform-plan",
        "commit_sha": "abc0007",
    },
    {
        "name": "Debug Assistant",
        "folder_name": "debug-assistant",
        "description": "Helps trace and fix runtime errors by reading stack traces and suggesting fixes.",
        "tags": ["debugging", "errors", "tracing"],
        "skill_md": "---\nname: Debug Assistant\ndescription: Trace and fix runtime errors.\ntags: [debugging]\n---\nAnalyze stack traces.",
        "content_hash": "hash-debug",
        "source": SkillSource.github,
        "source_url": "https://github.com/example/skills/debug-assistant",
        "repo": "example/skills",
        "repo_path": ".claude/skills/debug-assistant",
        "commit_sha": "abc0008",
    },
    {
        "name": "Test Coverage Report",
        "folder_name": "test-coverage",
        "description": "Generates a test coverage summary and suggests missing test cases.",
        "tags": ["testing", "coverage", "quality"],
        "skill_md": "---\nname: Test Coverage Report\ndescription: Generate coverage summary.\ntags: [testing, coverage]\n---\nReport coverage.",
        "content_hash": "hash-coverage",
        "source": SkillSource.github,
        "source_url": "https://github.com/example/skills/test-coverage",
        "repo": "example/skills",
        "repo_path": ".claude/skills/test-coverage",
        "commit_sha": "abc0009",
    },
    {
        "name": "Changelog Generator",
        "folder_name": "changelog",
        "description": "Generates a CHANGELOG.md from git history using conventional commit messages.",
        "tags": ["git", "changelog", "release"],
        "skill_md": "---\nname: Changelog Generator\ndescription: Generate CHANGELOG from git history.\ntags: [git, changelog]\n---\nGenerate changelog.",
        "content_hash": "hash-changelog",
        "source": SkillSource.github,
        "source_url": "https://github.com/example/skills/changelog",
        "repo": "example/skills",
        "repo_path": ".claude/skills/changelog",
        "commit_sha": "abc0010",
    },
]


@pytest_asyncio.fixture
async def seeded_db(db_session: AsyncSession) -> AsyncSession:
    """Insert SEED_SKILLS and flush (no commit so rollback cleans up)."""
    now = datetime.now(timezone.utc)
    for data in SEED_SKILLS:
        skill = Skill(
            id=uuid.uuid4(),
            created_at=now,
            updated_at=now,
            **data,
        )
        db_session.add(skill)
    await db_session.flush()
    return db_session

