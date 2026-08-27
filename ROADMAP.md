# ROADMAP — skilld

Phases are sequential. Don't start a phase's "nice to have" items before
its exit criteria are met.

## Phase 0 — Validate (done before any code)
- Manually use copy-pasted skills for a week to confirm the workflow
  gap is real.
- Confirm skills.sh scraping is allowed (ToS/robots.txt).
- Exit: can name the exact moment this tool would have saved time.

## Phase 1 — Menubar app MVP
- Static curated skill list (hardcoded, no backend yet).
- Install/update/remove into local skills folder.
- Exit: someone other than you installs a skill through the app and it
  works in their own Claude Code session unassisted.

## Phase 2 — Backend + skill index
- Scraper for skills.sh + curated GitHub repo list → Postgres.
- `GET /skills`, `GET /skills/{id}` with Postgres full-text search.
- Swap menubar app's hardcoded list for real API calls.
- Exit: 20 hand-picked test queries return sane top-3 results.

## Phase 3 — Browser extension MVP
- claude.ai content script, manual inject mode first.
- Auto-suggest toggle + preview popover.
- Add chatgpt.com support second.
- Exit: you use it as a daily driver for a week without turning it off.

## Phase 4 — Prompt clarifier
- On-device (Gemini Nano) rewrite by default.
- BYO API key as opt-in upgrade.
- Exit: blind before/after rating from 2-3 outside testers shows real
  improvement, not just added filler.

## Phase 5 — Polish / ship
- Semantic search only if keyword search is the proven bottleneck.
- Usage stats, favorites, custom local skill import.
- Store submissions (Chrome Web Store, Mac App Store) — budget review
  queue time.

## Ongoing, not a phase
- DOM selector maintenance as claude.ai/chatgpt.com ship UI changes.
- Keeping `ARCHITECTURE.md` in sync with actual endpoints/schema.
