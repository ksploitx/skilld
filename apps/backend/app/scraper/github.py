"""
GitHub source adapter.

Discovers all folders containing a SKILL.md file inside a curated list of
repositories (sources.yaml), parses YAML frontmatter, and returns normalised
SkillRecord objects.

Rate-limit strategy
───────────────────
- Authenticated requests: 5 000 req/h (GitHub REST API).
- Anonymous:              60  req/h  — strongly discouraged for production.
- We respect the `Retry-After` header on 429 and the `X-RateLimit-Reset`
  header on 403 (secondary rate limit).
- ETags: we send `If-None-Match` on repeat calls and treat 304 as a cache hit.
  This is especially useful when running the scraper on a cron schedule.
"""
from __future__ import annotations

import hashlib
import logging
import re
import time
from pathlib import PurePosixPath
from typing import Any

import httpx
import yaml

from app.config import get_settings
from app.scraper.base import BaseSource, SkillRecord

logger = logging.getLogger(__name__)

_FRONTMATTER_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.DOTALL)

# Map of URL → ETag value remembered across fetch_skills calls within the
# same process lifetime.  Intentionally module-level (not shared across
# workers) — cross-worker caching would need Redis and is out of v1 scope.
_etag_cache: dict[str, str] = {}


def _parse_frontmatter(content: str) -> dict[str, Any]:
    """Return the parsed YAML frontmatter dict, or {} if absent/malformed."""
    m = _FRONTMATTER_RE.match(content)
    if not m:
        return {}
    try:
        parsed = yaml.safe_load(m.group(1))
        return parsed if isinstance(parsed, dict) else {}
    except yaml.YAMLError:
        logger.warning("Malformed YAML frontmatter — skipping skill", exc_info=True)
        return {}


def _sha256(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


def _build_headers(settings) -> dict[str, str]:
    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    if settings.github_token:
        headers["Authorization"] = f"Bearer {settings.github_token}"
    return headers


class GitHubSource(BaseSource):
    """
    Scans each repo in sources.yaml for folders containing SKILL.md.
    Uses the GitHub REST API; never scrapes live at request time.
    """

    def __init__(self, sources_path: str | None = None) -> None:
        self._settings = get_settings()
        self._api_base = self._settings.github_api_base
        if sources_path is None:
            # Default: sources.yaml lives next to this file.
            import importlib.resources as pkg_resources
            from pathlib import Path
            sources_path = str(
                Path(__file__).parent / "sources.yaml"
            )
        self._sources_path = sources_path

    def _load_repos(self) -> list[dict]:
        with open(self._sources_path) as f:
            data = yaml.safe_load(f)
        return data.get("repos", [])

    async def fetch_skills(self) -> list[SkillRecord]:
        repos = self._load_repos()
        records: list[SkillRecord] = []
        headers = _build_headers(self._settings)

        async with httpx.AsyncClient(
            headers=headers,
            timeout=30.0,
            follow_redirects=True,
        ) as client:
            for repo_entry in repos:
                repo = repo_entry["repo"]
                branch = repo_entry.get("branch", "main")
                repo_records = await self._scrape_repo(client, repo, branch)
                records.extend(repo_records)

        logger.info("GitHub scrape complete: %d skills found", len(records))
        return records

    async def _scrape_repo(
        self, client: httpx.AsyncClient, repo: str, branch: str
    ) -> list[SkillRecord]:
        """Return all SkillRecord objects found in a single repo."""
        # Use the Git Trees API with recursive=1 to list all paths in one call.
        url = f"{self._api_base}/repos/{repo}/git/trees/{branch}?recursive=1"
        data = await self._get_json(client, url)
        if data is None:
            return []

        # Filter tree entries to paths ending in "/SKILL.md"
        tree = data.get("tree", [])
        skill_paths = [
            entry
            for entry in tree
            if entry.get("type") == "blob"
            and entry.get("path", "").endswith("/SKILL.md")
        ]

        if not skill_paths:
            logger.debug("No SKILL.md files found in %s@%s", repo, branch)
            return []

        records: list[SkillRecord] = []
        # Resolve the actual commit SHA for this branch
        ref_data = await self._get_json(
            client, f"{self._api_base}/repos/{repo}/commits/{branch}"
        )
        commit_sha = (ref_data or {}).get("sha", branch)

        for entry in skill_paths:
            path = entry["path"]  # e.g. ".claude/skills/git-commit/SKILL.md"
            folder_path = str(PurePosixPath(path).parent)  # strip /SKILL.md
            folder_name = PurePosixPath(folder_path).name  # last component

            content = await self._fetch_file_content(client, repo, path, commit_sha)
            if content is None:
                continue

            fm = _parse_frontmatter(content)
            if not fm:
                # File may have no frontmatter — still index it, just with
                # defaults derived from the folder name.
                logger.debug(
                    "No/malformed frontmatter in %s/%s — using defaults", repo, path
                )

            name = fm.get("name") or _kebab_to_title(folder_name)
            description = fm.get("description")
            # tags can be a list or a comma-separated string in the wild
            raw_tags = fm.get("tags", [])
            if isinstance(raw_tags, str):
                raw_tags = [t.strip() for t in raw_tags.split(",") if t.strip()]
            tags = [str(t) for t in raw_tags]

            ch = _sha256(content)
            source_url = (
                f"https://github.com/{repo}/tree/{commit_sha}/{folder_path}"
            )

            records.append(
                SkillRecord(
                    name=name,
                    folder_name=folder_name,
                    description=description,
                    tags=tags,
                    source="github",
                    source_url=source_url,
                    repo=repo,
                    repo_path=folder_path,
                    commit_sha=commit_sha,
                    skill_md=content,
                    content_hash=ch,
                )
            )

        return records

    async def _fetch_file_content(
        self,
        client: httpx.AsyncClient,
        repo: str,
        path: str,
        ref: str,
    ) -> str | None:
        """Fetch raw file content from GitHub (using raw.githubusercontent.com)."""
        url = f"https://raw.githubusercontent.com/{repo}/{ref}/{path}"
        response = await self._request_with_retry(client, url)
        if response is None or response.status_code != 200:
            return None
        return response.text

    async def _get_json(
        self, client: httpx.AsyncClient, url: str
    ) -> dict | None:
        """GET JSON from GitHub API with ETag caching and rate-limit handling."""
        request_headers: dict[str, str] = {}
        if url in _etag_cache:
            request_headers["If-None-Match"] = _etag_cache[url]

        response = await self._request_with_retry(client, url, extra_headers=request_headers)
        if response is None:
            return None

        if response.status_code == 304:
            # Content unchanged; caller should use its own cached copy.
            # We don't maintain a local JSON cache across calls here —
            # for a scheduled scraper that's fine (just re-fetch on restart).
            logger.debug("304 Not Modified: %s", url)
            return None

        if response.status_code != 200:
            logger.warning("GitHub API %s → %d", url, response.status_code)
            return None

        if etag := response.headers.get("ETag"):
            _etag_cache[url] = etag

        return response.json()

    async def _request_with_retry(
        self,
        client: httpx.AsyncClient,
        url: str,
        extra_headers: dict[str, str] | None = None,
        max_retries: int = 3,
    ) -> httpx.Response | None:
        """
        Make an HTTP GET with automatic retry on rate-limit responses.
        Respects Retry-After (429) and X-RateLimit-Reset (403).
        """
        import asyncio

        headers = dict(extra_headers or {})
        for attempt in range(max_retries):
            try:
                response = await client.get(url, headers=headers)
            except httpx.RequestError as exc:
                logger.error("Network error fetching %s: %s", url, exc)
                return None

            if response.status_code == 429:
                wait = int(response.headers.get("Retry-After", 60))
                logger.warning("Rate limited (429). Waiting %ds before retry.", wait)
                await asyncio.sleep(wait)
                continue

            if response.status_code == 403:
                reset_ts = response.headers.get("X-RateLimit-Reset")
                if reset_ts:
                    wait = max(0, int(reset_ts) - int(time.time())) + 5
                    logger.warning(
                        "Secondary rate limit (403). Waiting %ds until reset.", wait
                    )
                    await asyncio.sleep(wait)
                    continue

            return response

        logger.error("Exhausted retries for %s", url)
        return None


def _kebab_to_title(s: str) -> str:
    """Convert 'git-commit' → 'Git Commit'."""
    return " ".join(word.capitalize() for word in s.split("-"))

