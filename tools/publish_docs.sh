#!/usr/bin/env bash
# Publishes the documentation site to quarrowen.com/docs/ (the gh-pages branch, under `docs/` only):
#
#   tools/publish_docs.sh              # build and push
#   tools/publish_docs.sh --dry-run    # build, show what would change, push nothing
#
# **Only `docs/` is touched.** The same branch serves the download page and, more importantly,
# `update.json` and its signature - which the installed client polls, pinned to quarrowen.com. Writing
# the reference to the root would replace the landing page and break the updater for anything already
# installed. So this removes and rewrites one directory and leaves every other path alone, which is
# also what the user asked for: the docs *alongside* a landing page. (2026-09-24)
#
# Run by hand, or by the release job in .github/workflows/ci.yml so a release ships current docs.
set -euo pipefail
cd "$(dirname "$0")/.."

branch="${PAGES_BRANCH:-gh-pages}"
dry_run=0
[ "${1:-}" = "--dry-run" ] && dry_run=1

# The virtualenv is not in the repository; CI makes one, and a Mac may already have it.
venv="${DOCS_VENV:-.venv-docs}"
if [ ! -x "$venv/bin/mkdocs" ]; then
  echo "no mkdocs in $venv - creating it" >&2
  python3 -m venv "$venv"
  "$venv/bin/pip" install -q -r requirements-docs.txt
fi

# `--strict` on purpose: a broken link or a page missing from the nav fails the publish rather than
# going live. The site is small enough that this has never been a nuisance.
rm -rf build/docs
"$venv/bin/mkdocs" build --strict
[ -f build/docs/index.html ] || { echo "mkdocs produced no index.html" >&2; exit 1; }

work="$(mktemp -d "${TMPDIR:-/tmp}/quarrowen-docs.XXXXXX")"
trap 'git worktree remove --force "$work" 2>/dev/null || true; rm -rf "$work"' EXIT

# A fresh clone has the branch only as origin/$branch. Never start an orphan here: this branch already
# carries the release site, and orphaning it would throw that away - see the same guard in
# publish_site.sh, which learned it the hard way.
if ! git show-ref --verify --quiet "refs/heads/$branch"; then
  git fetch --quiet origin "$branch" 2>/dev/null && git branch --quiet "$branch" FETCH_HEAD 2>/dev/null || true
fi
git show-ref --verify --quiet "refs/heads/$branch" || {
  echo "no $branch branch - publish the release site first (tools/publish_site.sh)" >&2; exit 1; }
git worktree add --quiet "$work" "$branch"
git -C "$work" pull --quiet --ff-only origin "$branch" 2>/dev/null || true

# The one directory this owns. Removed wholesale so a page deleted upstream stops being served.
rm -rf "${work:?}/docs"
cp -R build/docs "$work/docs"

git -C "$work" add -A
if git -C "$work" diff --cached --quiet; then
  echo "docs already up to date"
  exit 0
fi

# **Refuse to push anything outside `docs/`.** The whole safety of this script is that one claim, and
# a claim a script does not check is a claim that holds until the day it does not - `update.json` and
# its signature are on this branch and the installed client is pinned to them. Cheap, and it turns a
# broken site into a failed run. (2026-09-24)
stray="$(git -C "$work" diff --cached --name-only | grep -v '^docs/' || true)"
if [ -n "$stray" ]; then
  echo "refusing to publish: this would change files outside docs/" >&2
  echo "$stray" >&2
  exit 1
fi

echo "changes to publish:"
git -C "$work" diff --cached --stat | tail -5
if [ "$dry_run" -eq 1 ]; then
  echo "(dry run - nothing pushed)"
  exit 0
fi

version="$(sed -n 's/^const GAME_VERSION := "\(.*\)"$/\1/p' engine/shared/protocol.gd)"
git -C "$work" commit -qm "Docs for $version"
git -C "$work" push -q origin "$branch"
echo "published to https://${PAGES_DOMAIN:-quarrowen.com}/docs/"
