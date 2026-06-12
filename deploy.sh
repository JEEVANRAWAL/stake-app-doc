#!/usr/bin/env bash
#
# deploy.sh — commit & publish the Stake planning docs.
#
# 1. Commits any local changes (message from $1, or a default).
# 2. Pushes source to `main` (renders on github.com).
# 3. Rebuilds and publishes the MkDocs site to GitHub Pages (gh-pages branch).
#
# Usage:
#   ./deploy.sh "your commit message"
#   ./deploy.sh                       # uses a default message
#
set -euo pipefail

cd "$(dirname "$0")"

MKDOCS="./.venv/bin/mkdocs"
MSG="${1:-Update docs}"

if [[ ! -x "$MKDOCS" ]]; then
  echo "✗ $MKDOCS not found. Create the venv first:"
  echo "    python3 -m venv .venv && ./.venv/bin/pip install mkdocs-material"
  exit 1
fi

# 1 + 2: commit & push source (skip cleanly if nothing changed)
if [[ -n "$(git status --porcelain)" ]]; then
  echo "→ Committing changes: $MSG"
  git add -A
  git commit -q -m "$MSG"
else
  echo "→ No local changes to commit."
fi

echo "→ Pushing source to main…"
git push -q origin main

# 3: publish the rendered site to GitHub Pages
echo "→ Building & deploying site to gh-pages…"
"$MKDOCS" gh-deploy --force

echo "✓ Done. Site: https://jeevanrawal.github.io/stake-app-doc/"
