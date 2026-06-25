#!/usr/bin/env bash
set -euo pipefail

# Find latest tag to calculate next version
latest_tag=$(git tag -l "v*.*.*" | sort -V | tail -n 1)
if [[ -z "$latest_tag" ]]; then
  latest_tag="v1.0.0"
fi

# Determine target version
arg="${1:-patch}"
if [[ "$arg" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  next_version="$arg"
else
  if [[ "$latest_tag" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    major="${BASH_REMATCH[1]}"
    minor="${BASH_REMATCH[2]}"
    patch="${BASH_REMATCH[3]}"
  else
    echo "Error: latest tag $latest_tag is not in vMAJOR.MINOR.PATCH format." >&2
    exit 1
  fi

  case "$arg" in
    patch)
      next_version="v${major}.${minor}.$((patch + 1))"
      ;;
    minor)
      next_version="v${major}.$((minor + 1)).0"
      ;;
    major)
      next_version="v$((major + 1)).0.0"
      ;;
    *)
      echo "Usage: $0 [vX.Y.Z | patch | minor | major]" >&2
      exit 2
      ;;
  esac
fi

echo "Latest version: $latest_tag"
echo "Target version: $next_version"

# Generate release notes at .github/release-notes/vX.Y.Z.md
notes_dir=".github/release-notes"
mkdir -p "$notes_dir"
notes_file="$notes_dir/${next_version}.md"

echo "Generating release notes at $notes_file..."
commit_list=""
raw_commits=""
if git rev-parse "$latest_tag" >/dev/null 2>&1; then
  raw_commits=$(git log "${latest_tag}..HEAD" --oneline)
else
  raw_commits=$(git log -n 10 --oneline)
fi

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  # Remove commit hash and trim spaces
  clean_msg=$(echo "$line" | sed -E 's/^[a-f0-9]+ //')
  # Only add if it's not a release commit or merge commit
  if [[ ! "$clean_msg" =~ ^release: && ! "$clean_msg" =~ ^Merge ]]; then
    commit_list="${commit_list}- ${clean_msg}\n"
  fi
done <<< "$raw_commits"

if [[ -z "$commit_list" ]]; then
  commit_list="- Preparing release ${next_version}\n"
fi

{
  echo "# Tora $next_version"
  echo ""
  echo "## Changes"
  echo ""
  printf "%b" "$commit_list"
  echo ""
  echo "## Included artifacts"
  echo ""
  echo "The release workflow publishes:"
  echo ""
  echo "- \`appcast.xml\`"
  echo "- \`Tora-${next_version}-macos.zip\`"
  echo "- \`Tora-${next_version}-macos.zip.sha256\`"
  echo "- \`Tora-${next_version}-macos.dmg\`"
  echo "- \`Tora-${next_version}-macos.dmg.sha256\`"
} > "$notes_file"

# Update CHANGELOG.md
changelog_file="CHANGELOG.md"
if [[ -f "$changelog_file" ]]; then
  echo "Updating $changelog_file..."
  today=$(date +%Y-%m-%d)
  new_entry="## ${next_version} - ${today}\n\n${commit_list}"
  content=$(cat "$changelog_file")

  updated_content=$(echo -e "$content" | awk -v entry="$new_entry" '
    BEGIN { inserted = 0 }
    /^## v/ && !inserted {
      print entry
      inserted = 1
    }
    { print }
  ')
  printf "%s\n" "$updated_content" > "$changelog_file"
fi

# Commit and push local changes
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Committing release notes, changelog and local changes..."
  git add -A
  git commit -m "release: prepare release $next_version"

  current_branch=$(git branch --show-current)
  echo "Pushing changes to remote branch $current_branch..."
  git push origin "$current_branch"
fi

# Run create-release script to tag and push the tag
echo "Tagging and pushing release tag $next_version..."
./Scripts/create-release.sh "$next_version"

# Monitor the GitHub Actions release workflow
echo "Waiting for GitHub Actions run to be created..."
run_id=""
for i in {1..30}; do
  run_id=$(env -u GITHUB_TOKEN gh run list --workflow=release.yml --json databaseId,headBranch --jq ".[] | select(.headBranch == \"$next_version\") | .databaseId" | head -n 1)
  if [[ -n "$run_id" ]]; then
    break
  fi
  sleep 2
done

if [[ -z "$run_id" ]]; then
  echo "Error: GitHub Actions release workflow run was not created within 60 seconds." >&2
  exit 1
fi

echo "Found workflow run ID: $run_id"
echo "Watching workflow run to completion..."
env -u GITHUB_TOKEN gh run watch "$run_id" --exit-status

echo "Release $next_version completed successfully!"
