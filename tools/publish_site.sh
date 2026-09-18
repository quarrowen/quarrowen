#!/usr/bin/env bash
# Publishes what tools/make_release.sh built to GitHub Pages (the gh-pages branch), and offers to attach
# the zips to a GitHub release:
#
#   tools/make_release.sh                 # build first
#   tools/publish_site.sh                 # then publish the page, update.json and mods.json (with signatures)
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
notes="${NOTES:-Quarrowen $version}"

[ -f "$out/index.html" ] || { echo "run tools/make_release.sh first (no $out/index.html)" >&2; exit 1; }
command -v gh >/dev/null || { echo "needs the GitHub CLI (gh)" >&2; exit 1; }

with_release=0
[ "${1:-}" = "--with-release" ] && with_release=1

# The site: a worktree on the pages branch so the main checkout is untouched.
work="$(mktemp -d "${TMPDIR:-/tmp}/quarrowen-pages.XXXXXX")"
trap 'git worktree remove --force "$work" 2>/dev/null || true; rm -rf "$work"' EXIT
# A fresh clone (CI) has the branch only as origin/$branch, or not at all. Get it from there before
# concluding it does not exist - starting an orphan branch over a site that already has one throws away
# every past version's folder, and the push is then refused as a non-fast-forward anyway.
if ! git show-ref --verify --quiet "refs/heads/$branch"; then
  git fetch --quiet origin "$branch" 2>/dev/null && git branch --quiet "$branch" FETCH_HEAD 2>/dev/null || true
fi
if git show-ref --verify --quiet "refs/heads/$branch"; then
  git worktree add --quiet "$work" "$branch"
  git -C "$work" pull --quiet --ff-only origin "$branch" 2>/dev/null || true
else
  git worktree add --quiet --detach "$work"
  git -C "$work" checkout --orphan "$branch"
  git -C "$work" rm -rq --cached . 2>/dev/null || true
  find "$work" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
fi

# Keep older versions' folders (old builds may still ask for them), replace everything else.
# Both manifests travel with their signature: a client that carries a release key ignores an unsigned
# update manifest, and the mod list does the same, so a missing .sig is an empty Mods page.
# The pictures of the game the page is built around. Copied as a folder rather than named one by one,
# so adding a screenshot never means remembering to edit this list - the page went live once with every
# image 404ing because of exactly that. (2026-09-18)
rm -rf "$work/shots"
[ -d "$out/shots" ] && cp -R "$out/shots" "$work/shots"
for f in index.html update.json update.json.sig mods.json mods.json.sig icon.png; do
  rm -f "$work/$f"
  [ -f "$out/$f" ] && cp "$out/$f" "$work/"
done
touch "$work/.nojekyll"  # serve files starting with an underscore, and skip Jekyll entirely
echo "${PAGES_DOMAIN:-quarrowen.com}" > "$work/CNAME"  # the custom domain the client's updater is pinned to
# The manifest has to point where the zips actually end up, or the game offers an update it cannot fetch.
manifest_url="$(sed -n 's/.*"url": "\(.*\)".*/\1/p' "$out/update.json" | head -1)"
case "$manifest_url" in
  */releases/download/*) points_at_release=1 ;;
  *) points_at_release=0 ;;
esac
if [ "$with_release" -eq 1 ] && [ "$points_at_release" -eq 0 ]; then
  echo "update.json points at $manifest_url, but --with-release puts the zips on the GitHub release." >&2
  echo "Rebuild with the release as the base first:" >&2
  echo "  BASE_URL=https://github.com/quarrowen/quarrowen/releases/download/$tag tools/make_release.sh" >&2
  exit 1
fi
if [ "$with_release" -eq 0 ] && [ "$points_at_release" -eq 1 ]; then
  echo "update.json points at the GitHub release, but this publish only serves the branch." >&2
  echo "Rebuild with the site as the base first:  BASE_URL=https://quarrowen.com tools/make_release.sh" >&2
  exit 1
fi

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
  # Everything the build produced, not a list kept by hand - a list forgets the disk image, and the site's
  # download button then points at a file that was never uploaded (it did, in 0.40.3).
  assets=()
  while IFS= read -r f; do assets+=("$f"); done < <(find "$out/v$version" -type f \( -name '*.zip' -o -name '*.dmg' \) | sort)
  [ "${#assets[@]}" -gt 0 ] || { echo "no release files in $out/v$version" >&2; exit 1; }
  # Whatever update.json and the page link to must be among them, or players get a 404 from a live page.
  # Every release-asset link anywhere on the page, not just the main button - the Windows download is an
  # ordinary link, and a check that only knows about one shape of button is the bug it is meant to catch.
  page_links="$(grep -o 'href="[^"]*/releases/download/[^"]*"' "$out/index.html" | sed 's/href="//; s/"$//' | sort -u)"
  for url in $(sed -n 's/.*"url": "\(.*\)".*/\1/p' "$out/update.json" "$out/mods.json") $page_links; do
    case "$url" in */releases/download/*) ;; *) continue ;; esac
    name="${url##*/}"
    printf '%s\n' "${assets[@]}" | grep -q "/$name$" || { echo "$name is linked but was not built - nothing would be uploaded for it" >&2; exit 1; }
  done
  if gh release view "$tag" >/dev/null 2>&1; then
    gh release upload "$tag" "${assets[@]}" --clobber
  else
    gh release create "$tag" "${assets[@]}" --title "Quarrowen $version" --notes "$notes"
  fi
  echo "release $tag updated"
fi

echo
echo "Pages serves https://quarrowen.com/ from the $branch branch (CNAME file included)."
echo "Turn it on once: Settings > Pages > Source: Deploy from a branch > $branch / (root), custom domain"
echo "quarrowen.com, Enforce HTTPS. DNS: four A records for the apex to 185.199.108-111.153, and"
echo "a CNAME for www to quarrowen.github.io."
