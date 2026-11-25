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
    upstream=""
    [[ -f "$dir/UPSTREAM" ]] && upstream="$(cat "$dir/UPSTREAM")"
    printf '%s %s\n' "$version" "${upstream:-$version}" > "$ROOT/state/$name.txt"
    packages+=("${built[@]}")
    log "$name $version"
done

(( ${#packages[@]} )) || die "no built packages found under $out"

tag="pkg-repo"
slug="${GITHUB_REPOSITORY:-yahya-azeem/pkg-overlay}"
if ! gh release view "$tag" -R "$slug" >/dev/null 2>&1; then
    gh release create "$tag" -R "$slug" \
        --title "pkg-overlay rolling repository" \
        --notes "Rolling pacman repository for yahya-azeem/pkg-overlay. See the README for the pacman.conf entry."
fi

# Seed the database from the release so packages that were not rebuilt in this
# run keep their entries. repo-add merges into an existing database.
base="https://github.com/$slug/releases/download/$tag"
for db in pkg-overlay.db.tar.zst pkg-overlay.files.tar.zst; do
    curl -fsSL --retry 3 --connect-timeout 15 "$base/$db" -o "$repo/$db" 2>/dev/null \
        || rm -f "$repo/$db"
done

log "updating pacman database"
repo-add --quiet "$repo/pkg-overlay.db.tar.zst" "${packages[@]}"

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
