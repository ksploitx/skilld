#!/usr/bin/env bash
# git-commit/scripts/stage-and-commit.sh
# Helper: stage all changes and open $EDITOR for commit message
set -euo pipefail

git add -A
git diff --cached --stat
git commit --verbose
