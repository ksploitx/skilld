# skilld — menubar app

macOS menu-bar app for browsing, installing, and removing Claude Code skills.

## Requirements
- macOS 14.0+
- Xcode 16+
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Setup

```bash
# From apps/menubar/
xcodegen generate      # (re)generate skilld.xcodeproj from project.yml
open skilld.xcodeproj
```

Then **Run** (⌘R) in Xcode or use xcodebuild:

```bash
xcodebuild build \
  -project skilld.xcodeproj \
  -scheme skilld \
  -destination "platform=macOS" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
```

## Running tests

```bash
xcodebuild test \
  -project skilld.xcodeproj \
  -scheme skilld \
  -destination "platform=macOS" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
```

## Project structure

```
apps/menubar/
├── project.yml                   # xcodegen spec — source of truth for the project
├── Resources/
│   ├── skills.json               # Bundled skill catalogue (name, description, folder, source_url)
│   └── skills/                   # 10 bundled skill folders
│       ├── python-expert/
│       │   ├── SKILL.md
│       │   └── examples/
│       ├── git-commit/
│       │   ├── SKILL.md
│       │   └── scripts/
│       └── ...                   # 8 more skills
├── skilld/
│   ├── SkillEntry.swift          # Codable value type for skills.json rows
│   ├── SkillInstaller.swift      # Pure logic: install/remove/hash — no UI
│   ├── SkillStore.swift          # @Observable view-model bridging installer → UI
│   ├── ContentView.swift         # Popover UI: search + list + action buttons
│   ├── skilldApp.swift           # App entry + NSStatusItem popover setup
│   └── Info.plist
└── skilldTests/
    ├── SkillInstallerTests.swift  # XCTest suite — all tests use a temp directory
    └── Info.plist
```

## Key design decisions

### Skills directory constant
`claudeSkillsDirectory` in `SkillInstaller.swift` is the single place
that defines `~/.claude/skills/`. Never hardcode this string anywhere
else. See `docs/CLAUDE_CODE_SKILLS.md` for why this path was chosen.

### Manifest tracking
`~/.claude/skilld-manifest.json` tracks every skill installed by this
app (folder name, install timestamp, SHA-256 content hash). The
installer will **refuse to delete** a skill folder it didn't install
itself, and will **refuse to overwrite** one unless it owns it.

### Content hashing
SHA-256 over all regular files in the skill folder, sorted by relative
path. Deterministic across installs — same tree = same hash. Used to
detect when a bundled skill has been updated relative to what's on disk.

### Phase 1 scope
- **No networking, no backend, no scraping.** The skill catalogue comes
  from the bundled `skills.json` and local skill folders.
- **No auth, no accounts.** Single-user, single-machine.
- Phase 2 will swap the bundled list for live `GET /skills` API calls.
