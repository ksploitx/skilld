# skilld — macOS menubar app

macOS menu-bar app for browsing, installing, and removing
[Claude Code skills](https://code.claude.com/docs/en/skills) with one click.

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 16+
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Backend API running (see `apps/backend/README.md`) or use the bundled offline catalog

## Setup

```bash
# From apps/menubar/
xcodegen generate      # (re)generate skilld.xcodeproj from project.yml
open skilld.xcodeproj
```

Then **Run** (⌘R) in Xcode, or build from the command line:

```bash
xcodebuild build \
  -project skilld.xcodeproj \
  -scheme skilld \
  -destination "platform=macOS" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
```

Click the brain icon (🧠) in the menu bar to open the skill browser.

## Running tests

```bash
xcodebuild test \
  -project skilld.xcodeproj \
  -scheme skilld \
  -destination "platform=macOS" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
```

All tests are offline — `MockURLProtocol` intercepts every URLSession request.

## How it works

### Catalog loading

1. On popover open, `SkillStore.refresh()` calls `GET /skills` on the backend.
2. The list updates live. Search input is debounced 300 ms before firing a new query.
3. If the backend is unreachable (`APIError.offline` / `.timeout`), the app falls back
   to the bundled `Resources/skills.json` and shows a yellow "Offline" banner.

### Install (online)

1. The API response includes `repo`, `repo_path`, and `commit_sha` for each skill.
2. `GitHubDownloader` fetches the tarball:
   `GET https://codeload.github.com/{owner}/{repo}/tar.gz/{commit_sha}`
3. The archive is extracted into a temp directory using `/usr/bin/tar`.
4. The skill subdirectory (`repo_path` within the archive root) is validated:
   - `SKILL.md` must exist
   - No `..` or absolute paths
   - No symlinks
   - Total size ≤ 5 MB, file count ≤ 100
5. Only fetches from: `github.com`, `api.github.com`, `codeload.github.com`
6. If validation passes, `SkillInstaller.installFromDirectory()` moves the folder
   atomically to `~/.claude/skills/<folder_name>/`.
7. On any failure, the temp directory is cleaned up — no partial folder is ever left.

### Install (offline)

If the skill has `source: "bundled"` (no real `repo`), the app installs from the
bundled `Resources/skills/<folder>/` folder instead.

### Remove

`SkillInstaller.removeByFolder()` deletes `~/.claude/skills/<folder>/` only if
the folder is tracked in `~/.claude/skilld-manifest.json`. Unmanaged folders
(created manually or by another tool) are never touched.

### Update detection

On popover open, `SkillStore` calls `GET /skills/updated-since?ts=<oldest_installed_at>`.
Any skill where the API's `commit_sha` differs from the manifest's `commit_sha`
gets an **"Update"** badge in the UI. Clicking Update re-downloads and swaps
the folder atomically.

### Offline fallback

`Resources/skills.json` is a `SkillSummary`-shaped JSON array (all API fields
present, with empty `repo`/`repo_path`/`commit_sha` for bundled entries). The
same decoder is used for both API responses and the fallback file.

## Safety rules

- Skills are installed to `~/.claude/skills/` only (the personal/global path).
- Folder names validated: lowercase-kebab-case, non-empty, no reserved names (`synced`, etc.).
- `~/.claude/skilld-manifest.json` tracks `folder`, `installedAt`, `contentHash`
  (SHA-256), and `commitSha`. Uninstall and overwrite both require manifest ownership.
- Security checks before any disk write: host allowlist, no path traversal,
  no symlinks, size cap, file count cap, SKILL.md required.
- Never execute anything from a skill.
- App Sandbox is OFF (`ENABLE_APP_SANDBOX: NO` in `project.yml`) — required to
  write to `~/.claude/skills/`.
- ATS localhost exception is set in `Info.plist` so `http://localhost:8000` works
  in dev without disabling ATS globally.

## Configuration

### Backend URL

Override the backend URL without changing code:

```bash
# Env var (highest priority)
SKILLD_API_BASE_URL=https://api.skilld.sh open skilld.app

# Or set SkilldAPIBaseURL in Info.plist (via Xcode build setting or project.yml)
```

Default is `http://localhost:8000` for local development.

## Project structure

```
apps/menubar/
├── project.yml                       # xcodegen spec — source of truth for the project
├── Resources/
│   ├── skills.json                   # Bundled offline catalog (SkillSummary-shaped JSON)
│   └── skills/                       # 10 bundled skill folders
│       ├── python-expert/SKILL.md
│       ├── git-commit/SKILL.md
│       └── ...
├── skilld/
│   ├── APIConfig.swift               # Base URL constant, timeouts, security limits
│   ├── APIError.swift                # Typed errors: offline, timeout, serverError, decodingError
│   ├── SkillsAPIClient.swift         # URLSession backend client + SkillSummary/Detail models
│   ├── GitHubDownloader.swift        # Download/extract/validate skill from GitHub tarball
│   ├── SkillInstaller.swift          # Atomic install/remove + manifest tracking (pure logic, no UI)
│   ├── SkillStore.swift              # @Observable view-model: API calls, debounce, offline fallback
│   ├── ContentView.swift             # Popover UI: search, list, offline banner, per-row actions
│   ├── skilldApp.swift               # App entry + NSStatusItem popover setup
│   └── Info.plist                    # LSUIElement=YES, ATS localhost exception
└── skilldTests/
    ├── MockURLProtocol.swift          # URLProtocol subclass for mocking URLSession
    ├── SkillsAPIClientTests.swift     # API decoding, server error, timeout, offline
    ├── GitHubDownloaderTests.swift    # Tarball install, security validations, cleanup on failure
    ├── SkillInstallerTests.swift      # Install/remove/update, unmanaged folder rejection
    └── Info.plist
```

## Key design decisions

| Decision | Rationale |
|---|---|
| Tarball API over Contents API | Single HTTP request; Contents API has 60/hr unauth rate limit |
| `/usr/bin/tar` over Swift tar library | Zero dependencies; ships with every macOS since forever |
| Combine debounce for search | Standard SwiftUI `@Observable` pattern; pairs naturally with `PassthroughSubject` |
| `SkillSummary` replaces `SkillEntry` | Avoids a mapping layer; same model for API + offline fallback |
| Manifest stores `commitSha` | Enables reliable update detection without re-hashing disk content |
| Atomic move on install | `FileManager.moveItem` is atomic on the same filesystem; no partial writes |
