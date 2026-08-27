# AGENTS.md — instructions for AI coding agents working on skilld

This file is read by Cursor, Antigravity, or any other AI coding agent
before making changes. Follow it over your own defaults when they
conflict.

## Read first
- `PRD.md` — what we're building and why, current v1 scope.
- `ARCHITECTURE.md` — component boundaries and data flow. Don't have
  the extension talk to Postgres directly, don't have the menubar app
  talk to GitHub directly, etc. — everything routes through the backend.

## Repo structure
```
apps/backend      FastAPI service — Python
apps/menubar      SwiftUI macOS app
apps/extension    Manifest V3 browser extension — TypeScript
packages/shared-types   TS interfaces shared by extension + future TS code
docs/             Planning docs (this file, PRD, ARCHITECTURE, ROADMAP)
```

A change to one app should not require touching another unless it's a
shared-types update or a genuine new backend endpoint both clients need.

## Working rules

1. **Stay in scope.** Only build what the current phase in `ROADMAP.md`
   calls for. Don't add semantic search, auth, or team features unless
   explicitly asked — v1 is keyword search, no auth, single user.

2. **Don't invent API contracts.** If a client needs a new backend
   endpoint, check `ARCHITECTURE.md`'s endpoint list first. If it's not
   there, propose the addition and update `ARCHITECTURE.md` in the same
   change — don't let the doc and code drift apart.

3. **DOM selectors in the extension are fragile by design of the
   problem, not by mistake.** Keep selector logic isolated per site
   (`apps/extension/src/sites/claude.ts`,
   `apps/extension/src/sites/chatgpt.ts`) so a breakage on one site
   doesn't require touching the other.

4. **No live scraping at request time.** The scraper worker is the only
   thing that talks to skills.sh/GitHub. The `/skills` search endpoint
   only ever reads from Postgres/Redis.

5. **Privacy default.** Anything that reads the user's draft message
   (auto-suggest matching, prompt clarifier) should run against local/
   cached data or on-device models unless the user has explicitly opted
   into a server-side/BYO-key mode. Don't add a network call that sends
   raw prompt text off-device without that opt-in gate existing first.

6. **Tests over trust.** Backend: pytest, at minimum a smoke test per
   new endpoint. Extension: Playwright E2E against real site DOM where
   feasible — these are the tests most likely to catch real breakage.
   Menubar: unit test any code that touches the filesystem (install/
   remove skill files) — this is the one place a bug can damage a
   user's real Claude Code setup.

7. **Ask before picking between equivalent tools.** If a task requires
   choosing between two roughly-equal libraries/approaches not already
   decided in `ARCHITECTURE.md`, ask rather than silently picking one.

8. **Style**: no unexplained magic strings for paths (e.g. the Claude
   Code skills folder path) — define once as a constant/config value.

## What "done" looks like for a task
- Code runs locally per the relevant app's README.
- New/changed endpoints reflected in `ARCHITECTURE.md`.
- No cross-app coupling introduced outside the documented backend
  contract.
- Tests added for the new behavior, not just happy-path manual checks.
