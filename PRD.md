# PRD — skilld

## Problem
People using Claude, ChatGPT, and Claude Code increasingly rely on "skills"
(SKILL.md files) to get better output. Finding the right skill for a given
task means manually browsing skills.sh or GitHub, copying file contents,
and pasting them into a chat, or manually placing files on disk for Claude
Code to pick up. This is slow and easy to forget to do.

## Goal
Reduce the gap between "I have a task" and "the right skill is loaded"
to near zero, across both chat-based AI (browser) and local AI tooling
(Claude Code via Mac menubar app).

## Non-goals (v1)
- Not building a skill authoring tool.
- Not hosting or re-publishing skill content ourselves beyond caching for
  search — link back to source, respect skills.sh terms.
- Not supporting Windows/Linux menubar equivalents yet (Mac only).
- Not doing semantic/embedding search in v1 — keyword search first.

## Users
Primarily developers already using Claude Code, Claude.ai, or ChatGPT
day-to-day and already skill-aware (not a beginner audience for v1).

## Core features (v1 scope)

### 1. Menubar app (macOS)
- Browse a curated + searchable list of skills.
- Install a skill into the local Claude Code skills folder with one click.
- Update / remove installed skills.
- See which skills are currently installed vs available.

### 2. Browser extension (Chrome, Manifest V3)
- Works on claude.ai first, chatgpt.com second.
- Manual mode: search and inject a skill's content into the current
  chat input.
- Auto-suggest mode (toggle): as the user types, suggest a relevant skill
  inline, non-intrusively.
- Preview a skill's content before injecting.

### 3. Prompt clarifier
- Optional rewrite of the user's draft message before sending, to make
  intent clearer to the model. On-device (Gemini Nano) by default; BYO
  API key as opt-in upgrade for better quality.

### 4. Shared backend
- Indexes skills from skills.sh + curated GitHub repos on a schedule.
- Serves search to both clients via one API.

## Success signals (v1)
- You personally stop manually copy-pasting skill files within 2 weeks
  of using the tool daily.
- At least 3 outside users install and use it for a week without asking
  "how do I do X" more than once.
- Suggestion false-positive rate low enough that auto-suggest mode stays
  on rather than getting toggled off in frustration.

## Out of scope questions to revisit later
- Team/shared skill libraries.
- Semantic search.
- Windows support.
- Monetization model.

## Key risks
- DOM selector breakage on claude.ai / chatgpt.com (ongoing maintenance
  cost, not a one-time risk).
- skills.sh scraping legality/rate limits — confirm ToS before Phase 2.
- Suggestion noise killing trust in auto-suggest mode.
