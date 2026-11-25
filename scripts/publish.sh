#!/usr/bin/env bash
# Collect built packages, rebuild the pacman database, publish a rolling
# GitHub release, and record the built versions in state/.
set -Eeuo pipefail

source "$(dirname -- "$0")/lib.sh"

git config --global --add safe.directory "$ROOT" 2>/dev/null || true

shopt -s nullglob
out="$ROOT/out"
repo="$out/repo"
mkdir -p "$repo"

packages=()
for dir in "$out"/*/; do
    name="$(basename "$dir")"
    [[ -f "$dir/VERSION" ]] || continue
    version="$(cat "$dir/VERSION")"

    sanitize_pkg_names "$dir"
    mapfile -t built < <(compgen -G "$dir/*.pkg.tar.zst" | grep -v -- '-debug-' | sort)
    (( ${#built[@]} )) || { warn "$name: no packages in $dir"; continue; }

    cp -f "${built[@]}" "$repo/"
    mkdir -p "$ROOT/state"
    printf '%s\n' "$version" > "$ROOT/state/$name.txt"
    packages+=("${built[@]}")
    log "$name $version"
done

(( ${#packages[@]} )) || die "no built packages found under $out"

log "generating pacman database"
repo-add --quiet "$repo/pkg-overlay.db.tar.zst" "${packages[@]}"

tag="pkg-repo"
if ! gh release view "$tag" -R "${GITHUB_REPOSITORY:-yahya-azeem/pkg-overlay}" >/dev/null 2>&1; then
    gh release create "$tag" -R "${GITHUB_REPOSITORY:-yahya-azeem/pkg-overlay}" \
        --title "pkg-overlay rolling repository" \
        --notes "Rolling pacman repository for yahya-azeem/pkg-overlay. See the README for the pacman.conf entry."
fi

assets=("$repo"/*.pkg.tar.zst "$repo"/pkg-overlay.db.tar.zst "$repo"/pkg-overlay.db \
        "$repo"/pkg-overlay.files.tar.zst "$repo"/pkg-overlay.files)
existing=()
for asset in "${assets[@]}"; do
    [[ -e "$asset" ]] && existing+=("$asset")
done

log "uploading ${#existing[@]} assets to release $tag"
gh release upload "$tag" "${existing[@]}" -R "${GITHUB_REPOSITORY:-yahya-azeem/pkg-overlay}" --clobber

if [[ ! -d "$ROOT/.git" ]]; then
    warn "not a git checkout; skipping state commit"
    exit 0
fi

git config user.name "pkg-overlay bot"
git config user.email "pkg-overlay@users.noreply.github.com"

git add state
if git diff --cached --quiet -- state; then
    log "state unchanged"
else
    git commit -m "state: record built package versions"
    git pull --rebase origin "${GITHUB_REF_NAME:-main}" || true
    git push origin "HEAD:${GITHUB_REF_NAME:-main}"
fi
