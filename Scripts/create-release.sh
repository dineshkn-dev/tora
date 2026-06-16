#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "Usage: $0 vMAJOR.MINOR.PATCH[-PRERELEASE]" >&2
  exit 2
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree must be clean before creating a release tag." >&2
  git status --short >&2
  exit 1
fi

./Scripts/release-check.sh
git tag -a "$version" -m "Release $version"
git push origin "$version"

echo "Pushed $version. GitHub Actions will build artifacts and create the release."
