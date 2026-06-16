#!/usr/bin/env bash
set -euo pipefail

git_dir="$(git rev-parse --git-dir)"
mkdir -p "$git_dir/hooks"

cp Scripts/hooks/pre-commit "$git_dir/hooks/pre-commit"
cp Scripts/hooks/pre-push "$git_dir/hooks/pre-push"
chmod +x "$git_dir/hooks/pre-commit" "$git_dir/hooks/pre-push"

echo "Installed Tora git hooks."
