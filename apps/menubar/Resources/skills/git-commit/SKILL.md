---
name: git-commit
description: Writes clear, conventional Git commit messages following the Conventional Commits 1.0 spec. Use whenever you need to commit changes or review staged diffs.
when_to_use: When the user asks to commit, stage, or write a commit message.
---

# Git Commit Helper

Write commit messages that follow the [Conventional Commits 1.0](https://www.conventionalcommits.org/en/v1.0.0/) specification.

## Format

```
<type>(<scope>): <short description>

[optional body]

[optional footer(s)]
```

## Types
- `feat` — new feature
- `fix` — bug fix
- `docs` — documentation only
- `style` — formatting, no logic change
- `refactor` — code restructure, no behaviour change
- `test` — tests only
- `chore` — build, tooling, CI

## Rules
1. Subject line ≤ 72 characters.
2. Use the imperative mood: "Add feature" not "Added feature".
3. Reference issue numbers in the footer: `Closes #123`.
4. Separate body from subject with a blank line.
5. Explain *why*, not *what* — the diff already shows what.
