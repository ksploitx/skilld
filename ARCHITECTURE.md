# ARCHITECTURE — skilld

## Overview
Three client-facing surfaces share one backend:

```
Browser extension  ─┐
                     ├──▶  Backend API (FastAPI)  ──▶  Postgres (skill index)
Menubar app        ─┘                              └─▶  Redis (search cache)
                                                          ▲
                                              Scraper worker (scheduled)
                                                          ▲
                                          skills.sh   +   GitHub repos
```

Neither client ever talks to Postgres, Redis, skills.sh, or GitHub
directly. All of that is fronted by the backend so client code stays
dumb and swappable, and so scraping/rate-limits live in one place.

## Components

### apps/backend (FastAPI)
- Owns the skill index. Source of truth for search.
- Endpoints (v1):
  - `GET /health`
  - `GET /skills?query=&tags=&limit=&offset=` — keyword search (Postgres
    full-text, ts_rank ranked; empty query returns recent skills)
  - `GET /skills/{id}` — full skill detail including raw SKILL.md
  - `GET /skills/updated-since?ts=` — used by menubar app to check for
    updates on installed skills
- Postgres: skill metadata + raw SKILL.md content, source, tags,
  timestamps, generated tsvector column with GIN index.
- Redis: caches hot search queries (60 s TTL). Not a source of truth — safe to
  flush.
- Scraper worker: `python -m app.scraper.run` — scheduled job (cron or simple
  worker process), pulls curated GitHub repos, normalises into the Skill
  schema, upserts into Postgres by (repo, repo_path) key. Skips unchanged
  content_hash. Runs independently of request time — search MUST never
  trigger a live scrape.

### apps/menubar (SwiftUI, macOS)
- Calls backend `/skills` to list/search and `/skills/updated-since` to check
  for updates on installed skills. Falls back to a bundled `skills.json` when
  the backend is unreachable, with an "offline" banner in the UI.
- Search input is debounced 300 ms before firing an API call. Local filtering
  is used only in offline mode.
- Installs a skill by fetching the folder tarball from GitHub
  (`codeload.github.com/{owner}/{repo}/tar.gz/{commit_sha}`) using
  `repo + repo_path + commit_sha` from the API response. Download goes to a
  temp directory first; the skill is validated (SKILL.md required, no path
  traversal, no symlinks, ≤ 5 MB / ≤ 100 files), then moved atomically into
  `~/.claude/skills/<folder_name>/`. On any failure, the temp dir is cleaned
  up — no partial folder is ever left behind. See `docs/CLAUDE_CODE_SKILLS.md`
  for the full filesystem convention.
- Only fetches content from: `github.com`, `api.github.com`,
  `codeload.github.com`. Redirects to other hosts are rejected.
- Tracks installed state locally (`~/.claude/skilld-manifest.json`) with
  `folder`, `installedAt`, `contentHash` (SHA-256), and `commitSha`.
  Manifest is never synced to backend in v1.
- Detects updates by comparing `commitSha` in the manifest against the
  API response from `/skills/updated-since`. Shows an "Update" badge per skill.
- Native AppKit/SwiftUI only — no cross-platform framework, since
  NSStatusItem + filesystem writes need native hooks.

New files added in this phase:
  `APIConfig.swift`        — base URL constant, overridable via Info.plist / env
  `APIError.swift`         — typed error enum (offline, timeout, serverError, decodingError)
  `SkillsAPIClient.swift`  — URLSession-based client for /skills endpoints
  `GitHubDownloader.swift` — download, extract, validate, and atomically install from GitHub

### apps/extension (TypeScript, Manifest V3)
- Content script per site (`claude.ai`, `chatgpt.com`) — separate
  selector configs per site since DOM structures differ and drift
  independently.
- MutationObserver tracks the input box (SPA route changes remount it).
- Manual inject: popup search → calls backend `/skills` → injects
  chosen skill's skill_md into the active input.
- Auto-suggest: debounced listener on input changes → backend query →
  inline suggestion chip. Keyword matching only in v1, runs against
  data already fetched from backend — no per-keystroke scraping.
- Prompt clarifier: on-device (Gemini Nano) rewrite by default; never
  sends draft text to our backend unless user opts into BYO API key mode.

### packages/shared-types
- TypeScript interfaces for `SkillSummary`, `SkillDetail`,
  `SkillSearchResponse`, `SkillSearchParams` — field-for-field match with
  backend Pydantic models, so extension and any future TS surface share one
  contract.

## Data model (v1)

```
Skill
  id            uuid (gen_random_uuid())
  name          text
  folder_name   text                    # e.g. "git-commit" (the /command name)
  description   text | null
  tags          text[]
  source        enum(github, skills_sh)
  source_url    text                    # canonical human URL
  repo          text                    # "owner/repo"
  repo_path     text                    # path inside repo to skill folder
  commit_sha    text                    # pinned — menubar fetches at install time
  skill_md      text                    # raw SKILL.md, for search only
  content_hash  text                    # SHA-256 of skill_md; scraper skips unchanged
  search_vector tsvector GENERATED ALWAYS AS (…) STORED
                                        # weighted: name(A) desc(B) tags(C) md(D)
  created_at    timestamptz
  updated_at    timestamptz

Indexes:
  ix_skills_search_vector  GIN on search_vector
  ix_skills_repo_path      UNIQUE on (repo, repo_path) — upsert key
  ix_skills_updated_at     B-tree on updated_at
```

## Local dev
`apps/backend/docker-compose.yml` spins up Postgres + Redis + API together.
Run the scraper separately with:
```
docker compose --profile scraper run scraper
# or locally:
cd apps/backend && python -m app.scraper.run
```

Menubar and extension point at `localhost` backend during dev via `.env` /
config, at a real deployed URL in production.

## Explicit decisions (revisit if wrong)
- Keyword/full-text search before embeddings — validate need first.
- On-device prompt clarifier before server-side — privacy-first default
  for a dev-tool audience.
- No auth in v1 — single shared backend, no per-user accounts yet.
- Menubar app talks to backend over plain HTTPS, no local socket to
  the extension — the two clients don't talk to each other, only to
  the shared backend.
- Scraper uses GitHub REST API (not GraphQL); ETag caching reduces rate
  limit usage on repeat cron runs.
- skills.sh adapter is a stub (SKILLS_SH_ENABLED=false) until ToS reviewed.
