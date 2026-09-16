#!/usr/bin/env bash
# Publishes what tools/make_release.sh built to GitHub Pages (the gh-pages branch), and offers to attach
# the zips to a GitHub release:
#
#   tools/make_release.sh                 # build first
#   tools/publish_site.sh                 # then publish the page, update.json and mods.json
#   tools/publish_site.sh --with-release  # and create/replace the GitHub release with the zips
#
# The page and the two JSON files are small and live in the branch; the zips are large, so they go to the
# release (release assets do not count against the repository and download without an account). The page
# links to whichever of the two is present - see docs/distribution.md.
set -euo pipefail
cd "$(dirname "$0")/.."

out=build/release
branch="${PAGES_BRANCH:-gh-pages}"
version="$(sed -n 's/^const GAME_VERSION := "\(.*\)"$/\1/p' engine/shared/protocol.gd)"
tag="v$version"
notes="${NOTES:-VoxelCraft $version}"

[ -f "$out/index.html" ] || { echo "run tools/make_release.sh first (no $out/index.html)" >&2; exit 1; }
command -v gh >/dev/null || { echo "needs the GitHub CLI (gh)" >&2; exit 1; }

with_release=0
[ "${1:-}" = "--with-release" ] && with_release=1

# The site: a worktree on the pages branch so the main checkout is untouched.
work="$(mktemp -d "${TMPDIR:-/tmp}/voxelcraft-pages.XXXXXX")"
trap 'git worktree remove --force "$work" 2>/dev/null || true; rm -rf "$work"' EXIT
if git show-ref --verify --quiet "refs/heads/$branch"; then
  git worktree add --quiet "$work" "$branch"
else
  git worktree add --quiet --detach "$work"
  git -C "$work" checkout --orphan "$branch"
  git -C "$work" rm -rq --cached . 2>/dev/null || true
  find "$work" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
fi

# Keep older versions' folders (old builds may still ask for them), replace everything else.
rm -f "$work/index.html" "$work/update.json" "$work/mods.json" "$work/icon.png"
cp "$out/index.html" "$out/update.json" "$out/mods.json" "$out/icon.png" "$work/"
touch "$work/.nojekyll"  # serve files starting with an underscore, and skip Jekyll entirely
if [ "$with_release" -eq 0 ]; then
  rm -rf "${work:?}/v$version"
  cp -R "$out/v$version" "$work/"   # no release assets: serve the zips from the page itself
fi

git -C "$work" add -A
if git -C "$work" diff --cached --quiet; then
  echo "site already up to date"
else
  git -C "$work" commit -qm "Site for $tag"
  git -C "$work" push -q origin "$branch"
  echo "pushed $branch"
fi

if [ "$with_release" -eq 1 ]; then
  if gh release view "$tag" >/dev/null 2>&1; then
    gh release upload "$tag" "$out/v$version"/*.zip "$out/v$version"/mods/*.zip --clobber
  else
    gh release create "$tag" "$out/v$version"/*.zip "$out/v$version"/mods/*.zip \
      --title "VoxelCraft $version" --notes "$notes"
  fi
  echo "release $tag updated"
fi

echo
echo "Pages serves https://omnivoxel-game.github.io/voxelcraft/ from the $branch branch."
echo "Turn it on once: repository Settings > Pages > Source: Deploy from a branch > $branch / (root)."
