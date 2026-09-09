# Claude Code Skills — Filesystem Convention

Research doc for the skilld menubar app's install/uninstall logic.
Answers the five questions raised before implementation.

> **Primary source**: [Extend Claude with skills](https://code.claude.com/docs/en/skills)
> (official Claude Code documentation, accessed 2026-09-09).
> Additional context from [Explore the .claude directory](https://code.claude.com/docs/en/claude-directory).

---

## 1. Filesystem path

Claude Code discovers skills from multiple locations. The two relevant
to our menubar app are:

| Scope | Path | When it loads |
|---|---|---|
| **Personal (user-level, global)** | `~/.claude/skills/<skill-name>/SKILL.md` | Every project on this machine |
| **Project-level** | `<repo>/.claude/skills/<skill-name>/SKILL.md` | Sessions in that repository |

There is **no** `~/Library/Application Support/Claude Code/skills/`
path on macOS — some third-party articles cite this, but the official
docs use `~/.claude/skills/` for personal skills.

**For our menubar app**: we install to `~/.claude/skills/<skill-name>/`
(the personal/global location) so the skill is available across all
projects without the user needing to be inside a specific repo.

> **Source**: [Choose where skills load](https://code.claude.com/docs/en/skills#where-skills-live)

### Other locations (not relevant to our install logic)

- **Enterprise**: `.claude/skills/` in the managed-settings directory
  (deployed by org admins).
- **Nested / monorepo**: `<subdir>/.claude/skills/<skill-name>/SKILL.md`.
- **Plugin**: `<plugin>/skills/<skill-name>/SKILL.md`.
- **claude.ai account**: synced skills from the web UI.

### Precedence when names collide

Enterprise > Personal (`~/.claude/`) > Project (`.claude/`).

> **Source**: [Resolve skills that share a name](https://code.claude.com/docs/en/skills#resolve-skills-that-share-a-name)

---

## 2. Required folder / file structure

Each skill lives in its own subdirectory containing a `SKILL.md` file:

```
~/.claude/skills/
└── <skill-name>/
    ├── SKILL.md          # required — the skill definition
    ├── scripts/          # optional — supporting files
    ├── examples/         # optional
    └── ...               # any other supporting files
```

- **One `SKILL.md` per skill directory** — this is the only required
  file. The directory name becomes the command you type (`/skill-name`).
- Additional files (scripts, templates, examples) can live alongside
  `SKILL.md`. Skills can reference them via relative paths. The
  `${CLAUDE_SKILL_DIR}` variable expands to the directory containing
  `SKILL.md`.
- A flat `.md` file in `.claude/commands/` is the **legacy** format and
  still works, but the official docs recommend the `skills/` directory
  format for new work.

> **Source**: [Create your first skill](https://code.claude.com/docs/en/skills#create-your-first-skill)
> and [Command files note](https://code.claude.com/docs/en/skills#where-skills-live)

---

## 3. Frontmatter / metadata format

`SKILL.md` uses **YAML frontmatter** between `---` markers at the very
top of the file. The opening `---` **must be the first line** of the
file, or Claude Code treats the entire file as skill content.

### Minimal example

```yaml
---
description: What this skill does and when to use it.
---

Your instructions here…
```

### All frontmatter fields

All fields are optional. Only `description` is recommended.

| Field | Required | Purpose |
|---|---|---|
| `name` | No | Display name. Defaults to directory name. |
| `description` | Recommended | What the skill does and when Claude should use it. Truncated at 1,536 chars in listings. |
| `when_to_use` | No | Extra trigger context, appended to description. |
| `argument-hint` | No | Autocomplete hint, e.g. `[issue-number]`. |
| `arguments` | No | Named positional arguments for `$name` substitution. |
| `disable-model-invocation` | No | `true` = user-only, Claude won't auto-invoke. Default `false`. |
| `user-invocable` | No | `false` = hidden from `/` menu, only Claude invokes it. Default `true`. |
| `allowed-tools` | No | Tools granted without asking permission during this skill's turn. |
| `disallowed-tools` | No | Tools removed from Claude's pool while skill is active. |
| `model` | No | Override session model while skill is active. |
| `effort` | No | Override effort level (`low`/`medium`/`high`/`xhigh`/`max`). |
| `context` | No | `fork` to run in a forked subagent context. |
| `agent` | No | Subagent type when `context: fork`. |
| `background` | No | With `context: fork`, `false` waits for result. Default `true`. |
| `hooks` | No | Hooks registered when skill is invoked. |
| `paths` | No | Glob patterns limiting when Claude auto-loads the skill. |
| `shell` | No | `bash` (default) or `powershell` for `!` commands. |
| `metadata` | No | Free-form YAML map for your own tooling. Claude Code ignores it. |
| `license` | No | License field (Agent Skills spec). Claude Code accepts but doesn't act on it. |
| `compatibility` | No | Environment requirements (Agent Skills spec). |

Boolean fields accept `yes`/`no`/`on`/`off`/`1`/`0`/`true`/`false`
(case-insensitive).

> **Source**: [Frontmatter reference](https://code.claude.com/docs/en/skills#frontmatter-reference)

### What our install logic needs to write

At minimum, a valid installed skill needs:
1. The directory `~/.claude/skills/<skill-name>/`
2. A `SKILL.md` file containing the skill's `raw_content` from our
   backend (which already includes the `---` frontmatter block and
   markdown body).

---

## 4. Restart / reload behavior

**No restart required.** Claude Code watches skill directories for file
changes at runtime (except in bare mode). When you add, edit, or remove
a skill under `~/.claude/skills/` or the project `.claude/skills/`,
Claude Code picks up the change within the current session.

**Caveat**: If the top-level `skills/` directory itself didn't exist
when the session started, a restart is needed so Claude Code can begin
watching it. Once the directory exists and is being watched, adding
new skill subdirectories is detected live.

> **Source**: [Edit a skill during a session](https://code.claude.com/docs/en/skills#live-change-detection)

### Implication for our app

Our install logic should ensure `~/.claude/skills/` exists before
writing. If this is the first skill ever installed and the directory
was just created, the user may need to restart their Claude Code
session once. We should show a note about this in the UI.

---

## 5. Skill folder naming constraints

The official docs do not specify strict naming rules (e.g. lowercase
only, no spaces), but the following constraints can be inferred:

- **The directory name becomes the `/` command**: `/deploy` maps to a
  folder named `deploy`. This means the name must be valid as a
  slash-command identifier.
- **Reserved name**: `synced` is reserved — Claude Code uses
  `~/.claude/skills/synced/` for skills downloaded from claude.ai.
  Do not name a skill `synced` in any capitalization.
- **Practical convention**: All official examples and the getting-started
  tutorial use **lowercase-kebab-case** (`summarize-changes`,
  `api-conventions`, etc.). No examples use spaces, uppercase, or
  underscores.
- **Name collisions**: if a skill name matches a built-in command or
  bundled skill, your skill replaces it (but not aliases). Avoid names
  like `help`, `compact`, `doctor`, `code-review`, `debug`, `batch`.

> **Source**: Inferred from examples in [Create your first skill](https://code.claude.com/docs/en/skills#create-your-first-skill)
> and the [reserved name note](https://code.claude.com/docs/en/skills#where-skills-live).

### Recommendation for our app

Normalize skill names to **lowercase-kebab-case** during install
(e.g. `"Python Expert"` → `python-expert`). This matches the
community convention and avoids filesystem edge cases.

---

## Open questions

1. **Exact character set for folder names** — the docs don't specify
   whether non-ASCII characters, dots, or underscores are valid in
   skill directory names. Sticking to `[a-z0-9-]` (lowercase
   alphanumeric + hyphens) is safest until tested.

2. **Maximum skill name length** — not documented. File system limits
   apply (255 chars on APFS/HFS+), but the `/` command UI may truncate
   earlier.

3. **Symlink support** — the docs confirm that a skill directory entry
   can be a symlink. We could potentially use this for install
   management, but it adds complexity with no clear benefit for v1.

4. **`~/.claude/` creation** — unclear whether Claude Code creates
   `~/.claude/` on first run or if it must exist. Our install logic
   should `mkdir -p` both `~/.claude/` and `~/.claude/skills/` to be
   safe.
