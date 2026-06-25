---
name: release-automation
description: Automates the entire release process, including version increment, commits, tags, release creation, and GitHub workflow monitoring.
---

# Release Automation Skill

This skill automates the entire release flow for the Tora application.

## Triggering the Skill

You can trigger this skill by asking the assistant to perform a release, e.g.:
- "Run the release-automation skill for patch"
- "Create a new release minor"
- "Trigger release-automation v1.3.0"

## Execution Steps

1. **Verify Prerequisites**:
   - Ensure the user is logged into GitHub CLI (`env -u GITHUB_TOKEN gh auth status`).
2. **Execute Automation Script**:
   - Run the script located at `.agents/skills/release-automation/scripts/automate-release.sh` passing the target version or increment type (e.g. `patch`, `minor`, `major`, or `vX.Y.Z`).
3. **Monitor Status**:
   - The script will build, test, generate release notes, commit/push changes, tag the commit, push the tag, and wait for GitHub Actions to build and publish the release.
   - If the script fails, report the error logs to the user.
