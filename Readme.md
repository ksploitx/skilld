# skilld

Browser extension + Mac menubar app that suggests and injects the right
AI skill (from skills.sh, GitHub, or your own library) into Claude/
ChatGPT before you hit send — plus a local skill manager for Claude Code
and a built-in prompt clarifier.

## Start here
- `PRD.md` — what we're building, for whom, v1 scope.
- `ARCHITECTURE.md` — how the three apps and backend fit together.
- `ROADMAP.md` — build order and exit criteria per phase.
- `AGENTS.md` — rules for AI coding agents (Cursor/Antigravity) working
  in this repo. Read this before generating code here.

## Repo layout
```
apps/backend      FastAPI service
apps/menubar      SwiftUI macOS app
apps/extension    Manifest V3 browser extension
packages/shared-types   Shared TS types
```

## Local dev
See each app's own README under `apps/<name>/README.md` once scaffolded.
Root `docker-compose.yml` runs backend + Postgres + Redis together.
