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
  - `GET /skills?query=&tags=` — keyword search (Postgres full-text,
    not embeddings, for v1)
  - `GET /skills/{id}`
  - `GET /skills/updated-since?ts=` — used by menubar app to check for
    updates on installed skills
- Postgres: skill metadata + raw SKILL.md content, source, tags,
  timestamps.
- Redis: caches hot search queries. Not a source of truth — safe to
  flush.
- Scraper worker: scheduled job (cron or simple worker process), pulls
  skills.sh + a curated GitHub repo list, normalizes into the Skill
  schema, upserts into Postgres. Runs independently of request time —
  search must never trigger a live scrape.

### apps/menubar (SwiftUI, macOS)
- Calls backend `/skills` to list/search.
- Installs a skill by writing its raw_content to
  `~/.claude/skills/<skill-name>/SKILL.md` (confirm exact path Claude
  Code expects before wiring this).
- Tracks installed state locally (simple local JSON manifest of
  installed skill ids + versions, not synced to backend in v1).
- Native AppKit/SwiftUI only — no cross-platform framework, since
  NSStatusItem + file system watching need native hooks.

### apps/extension (TypeScript, Manifest V3)
- Content script per site (`claude.ai`, `chatgpt.com`) — separate
  selector configs per site since DOM structures differ and drift
  independently.
- MutationObserver tracks the input box (SPA route changes remount it).
- Manual inject: popup search → calls backend `/skills` → injects
  chosen skill's raw_content into the active input.
- Auto-suggest: debounced listener on input changes → backend query →
  inline suggestion chip. Keyword matching only in v1, runs against
  data already fetched from backend — no per-keystroke scraping.
- Prompt clarifier: on-device (Gemini Nano) rewrite by default; never
  sends draft text to our backend unless user opts into BYO API key mode.

### packages/shared-types
- TypeScript interfaces for `Skill`, `SkillSearchResult` — field-for-
  field match with backend Pydantic models, so extension and any future
  TS surface share one contract.

## Data model (v1)

```
Skill
  id            uuid
  name          string
  description   string
  tags          string[]
  source        enum(skills_sh, github)
  source_url    string
  raw_content   text          # full SKILL.md
  created_at    timestamp
  updated_at    timestamp
```

## Local dev
`docker-compose.yml` at repo root spins up Postgres + Redis + backend
together. Menubar and extension point at `localhost` backend during dev
via `.env` / config, at a real deployed URL in production.

## Explicit decisions (revisit if wrong)
- Keyword/full-text search before embeddings — validate need first.
- On-device prompt clarifier before server-side — privacy-first default
  for a dev-tool audience.
- No auth in v1 — single shared backend, no per-user accounts yet.
- Menubar app talks to backend over plain HTTPS, no local socket to
  the extension — the two clients don't talk to each other, only to
  the shared backend.
