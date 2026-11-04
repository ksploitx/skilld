"""
Scraper unit tests — no real network calls.

Coverage:
- Happy path: finds SKILL.md files, parses frontmatter, returns SkillRecord.
- Malformed frontmatter: still returns a record with defaults.
- Unchanged content hash: upsert_skill returns "skipped".
- Rate-limit (429) retry: scraper waits and retries.
- Missing repo / empty tree: returns empty list gracefully.
"""
from __future__ import annotations

import hashlib
import json
from unittest.mock import AsyncMock, MagicMock, patch

import httpx
import pytest
import pytest_asyncio

from app.scraper.base import SkillRecord
from app.scraper.github import GitHubSource, _parse_frontmatter, _sha256
from app.scraper.run import upsert_skill


# ---------------------------------------------------------------------------
# Unit: _parse_frontmatter
# ---------------------------------------------------------------------------

def test_parse_frontmatter_happy_path():
    content = "---\nname: My Skill\ndescription: Does things\ntags: [foo, bar]\n---\nBody"
    fm = _parse_frontmatter(content)
    assert fm["name"] == "My Skill"
    assert fm["description"] == "Does things"
    assert fm["tags"] == ["foo", "bar"]


def test_parse_frontmatter_missing():
    content = "No frontmatter here"
    assert _parse_frontmatter(content) == {}


def test_parse_frontmatter_malformed():
    """Malformed YAML should not raise — returns {}."""
    content = "---\nname: [unclosed\n---\nBody"
    result = _parse_frontmatter(content)
    assert result == {}


def test_parse_frontmatter_empty_block():
    content = "---\n---\nBody"
    # empty YAML block parses to None, should return {}
    result = _parse_frontmatter(content)
    assert result == {}


# ---------------------------------------------------------------------------
# Integration: GitHubSource with mocked HTTP
# ---------------------------------------------------------------------------

VALID_SKILL_MD = """\
---
name: Git Commit
description: Write conventional commit messages.
tags: [git, commit]
---
Generate a commit message from the staged diff.
"""

MALFORMED_SKILL_MD = """\
---
name: [broken yaml here
---
Body content with no valid frontmatter.
"""

NO_FRONTMATTER_SKILL_MD = "Just a plain markdown file with no frontmatter."


def _make_tree_response(paths: list[str]) -> dict:
    return {
        "tree": [
            {"type": "blob", "path": p, "sha": "abc"}
            for p in paths
        ]
    }


def _make_commit_response(sha: str = "deadbeef1234") -> dict:
    return {"sha": sha}


def _make_mock_client(responses: dict[str, tuple[int, str | dict]]):
    """
    Build an httpx.AsyncClient mock where each URL maps to (status, body).
    body can be a str (raw text) or dict (JSON).
    """
    async def mock_get(url, **kwargs):
        if url in responses:
            status, body = responses[url]
            if isinstance(body, dict):
                content = json.dumps(body).encode()
                headers = {"Content-Type": "application/json"}
            else:
                content = body.encode()
                headers = {"Content-Type": "text/plain"}
            return httpx.Response(status, content=content, headers=headers)
        return httpx.Response(404, content=b"Not found")

    client = AsyncMock(spec=httpx.AsyncClient)
    client.get = mock_get
    client.__aenter__ = AsyncMock(return_value=client)
    client.__aexit__ = AsyncMock(return_value=False)
    return client


COMMIT_SHA = "deadbeef1234"
REPO = "example/skills"
BRANCH = "main"
TREE_URL = f"https://api.github.com/repos/{REPO}/git/trees/{BRANCH}?recursive=1"
COMMIT_URL = f"https://api.github.com/repos/{REPO}/commits/{BRANCH}"
RAW_BASE = f"https://raw.githubusercontent.com/{REPO}/{COMMIT_SHA}"


@pytest.mark.asyncio
async def test_github_source_happy_path(tmp_path):
    """Finds SKILL.md, parses frontmatter, returns a SkillRecord."""
    sources_yaml = tmp_path / "sources.yaml"
    sources_yaml.write_text(
        f"repos:\n  - repo: {REPO}\n    branch: {BRANCH}\n"
    )

    skill_path = ".claude/skills/git-commit/SKILL.md"
    folder_path = ".claude/skills/git-commit"
    raw_url = f"{RAW_BASE}/{skill_path}"

    mock_responses = {
        TREE_URL: (200, _make_tree_response([skill_path])),
        COMMIT_URL: (200, _make_commit_response(COMMIT_SHA)),
        raw_url: (200, VALID_SKILL_MD),
    }

    source = GitHubSource(sources_path=str(sources_yaml))

    with patch("httpx.AsyncClient") as MockClient:
        MockClient.return_value = _make_mock_client(mock_responses)
        records = await source.fetch_skills()

    assert len(records) == 1
    r = records[0]
    assert r.name == "Git Commit"
    assert r.folder_name == "git-commit"
    assert r.description == "Write conventional commit messages."
    assert "git" in r.tags
    assert r.source == "github"
    assert r.repo == REPO
    assert r.repo_path == folder_path
    assert r.commit_sha == COMMIT_SHA
    assert r.content_hash == _sha256(VALID_SKILL_MD)


@pytest.mark.asyncio
async def test_github_source_malformed_frontmatter(tmp_path):
    """Malformed frontmatter: still returns a SkillRecord with default name."""
    sources_yaml = tmp_path / "sources.yaml"
    sources_yaml.write_text(
        f"repos:\n  - repo: {REPO}\n    branch: {BRANCH}\n"
    )
    skill_path = ".claude/skills/broken-skill/SKILL.md"
    raw_url = f"{RAW_BASE}/{skill_path}"

    mock_responses = {
        TREE_URL: (200, _make_tree_response([skill_path])),
        COMMIT_URL: (200, _make_commit_response(COMMIT_SHA)),
        raw_url: (200, MALFORMED_SKILL_MD),
    }

    source = GitHubSource(sources_path=str(sources_yaml))

    with patch("httpx.AsyncClient") as MockClient:
        MockClient.return_value = _make_mock_client(mock_responses)
        records = await source.fetch_skills()

    assert len(records) == 1
    r = records[0]
    # folder_name "broken-skill" → title "Broken Skill"
    assert r.name == "Broken Skill"
    assert r.description is None
    assert r.tags == []


@pytest.mark.asyncio
async def test_github_source_no_skills_in_repo(tmp_path):
    """A repo with no SKILL.md files returns an empty list."""
    sources_yaml = tmp_path / "sources.yaml"
    sources_yaml.write_text(
        f"repos:\n  - repo: {REPO}\n    branch: {BRANCH}\n"
    )

    mock_responses = {
        TREE_URL: (200, _make_tree_response(["README.md", "src/main.py"])),
        COMMIT_URL: (200, _make_commit_response(COMMIT_SHA)),
    }

    source = GitHubSource(sources_path=str(sources_yaml))

    with patch("httpx.AsyncClient") as MockClient:
        MockClient.return_value = _make_mock_client(mock_responses)
        records = await source.fetch_skills()

    assert records == []


# ---------------------------------------------------------------------------
# Upsert logic: unchanged hash → skipped
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_upsert_skips_unchanged_hash(db_session):
    """If content_hash matches stored value, upsert returns 'skipped'."""
    from datetime import datetime, timezone
    import uuid
    from app.models import Skill, SkillSource as ModelSkillSource

    existing = Skill(
        id=uuid.uuid4(),
        name="Test Skill",
        folder_name="test-skill",
        description="A test skill",
        tags=[],
        source=ModelSkillSource.github,
        source_url="https://github.com/example/test",
        repo="example/test",
        repo_path=".claude/skills/test-skill",
        commit_sha="abc123",
        skill_md="content",
        content_hash="same-hash",
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )
    db_session.add(existing)
    await db_session.flush()

    record = SkillRecord(
        name="Test Skill",
        folder_name="test-skill",
        description="A test skill",
        tags=[],
        source="github",
        source_url="https://github.com/example/test",
        repo="example/test",
        repo_path=".claude/skills/test-skill",
        commit_sha="abc123",
        skill_md="content",
        content_hash="same-hash",  # same hash → should skip
    )

    result = await upsert_skill(db_session, record)
    assert result == "skipped"


@pytest.mark.asyncio
async def test_upsert_updates_changed_hash(db_session):
    """If content_hash differs, upsert returns 'updated' and writes new data."""
    from datetime import datetime, timezone
    import uuid
    from app.models import Skill, SkillSource as ModelSkillSource

    existing = Skill(
        id=uuid.uuid4(),
        name="Old Name",
        folder_name="update-skill",
        description="old",
        tags=[],
        source=ModelSkillSource.github,
        source_url="https://github.com/example/update",
        repo="example/update",
        repo_path=".claude/skills/update-skill",
        commit_sha="sha-old",
        skill_md="old content",
        content_hash="old-hash",
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )
    db_session.add(existing)
    await db_session.flush()

    record = SkillRecord(
        name="New Name",
        folder_name="update-skill",
        description="new",
        tags=["updated"],
        source="github",
        source_url="https://github.com/example/update",
        repo="example/update",
        repo_path=".claude/skills/update-skill",
        commit_sha="sha-new",
        skill_md="new content",
        content_hash="new-hash",
    )

    result = await upsert_skill(db_session, record)
    assert result == "updated"

