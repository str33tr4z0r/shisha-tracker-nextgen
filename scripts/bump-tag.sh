#!/usr/bin/env bash
set -euo pipefail
# Script to bump the git tag version (SemVer) and push it to origin.
# Patch bump (v1.2.3 -> v1.2.4)
#./bump-tag.sh

# Minor bump (v1.2.3 -> v1.3.0)
#./bump-tag.sh minor

# Major bump (v1.2.3 -> v2.0.0)
#./bump-tag.sh major

# Wenn dein Arbeitsbaum uncommitted Änderungen hat:
#./bump-tag.sh patch --allow-dirty


# Usage: ./bump-tag.sh [patch|minor|major] [--allow-dirty]
BUMP_KIND="${1:-patch}"
ALLOW_DIRTY="${2:-}"
case "$BUMP_KIND" in
  patch|minor|major) ;;
  *) echo "Usage: $0 [patch|minor|major] [--allow-dirty]"; exit 2;;
esac

# 1) Checks
command -v git >/dev/null || { echo "git not found"; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "Not a git repo"; exit 1; }

if [ "$ALLOW_DIRTY" != "--allow-dirty" ]; then
  if [ -n "$(git status --porcelain)" ]; then
    echo "Working tree not clean. Commit or stash changes, or pass --allow-dirty."; exit 1
  fi
fi

git remote get-url origin >/dev/null 2>&1 || { echo "No 'origin' remote."; exit 1; }

# 2) Make sure we have up-to-date tags
git fetch --tags --prune --force

# 3) Find last tag (SemVer vX.Y.Z). If none -> v0.0.0
LAST_TAG=$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' 2>/dev/null || echo "v0.0.0")

# 4) Parse and bump
VER="${LAST_TAG#v}"
IFS='.' read -r MA MI PA <<<"$VER"

case "$BUMP_KIND" in
  patch) NEW_TAG="v${MA}.${MI}.$((PA+1))" ;;
  minor) NEW_TAG="v${MA}.$((MI+1)).0" ;;
  major) NEW_TAG="v$((MA+1)).0.0" ;;
esac

# 5) Create annotated tag on current HEAD
echo "Last tag: $LAST_TAG"
echo "New tag : $NEW_TAG"
git tag -a "$NEW_TAG" -m "Release $NEW_TAG"

# 6) Push tag (and make sure branch is pushed first)
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "HEAD" ]; then
  # Push branch so the tag points to a commit visible on origin
  git push origin "$CURRENT_BRANCH"
fi
git push origin "$NEW_TAG"

echo "Done. Pushed tag $NEW_TAG to origin."
