#!/usr/bin/env bash
# Shared helpers for the pkg-overlay scripts. Sourced, not executed.
# shellcheck shell=bash

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m==>\033[0m %s\n' "$*" >&2; exit 1; }

package_dirs() {
    find "$ROOT/packages" -mindepth 1 -maxdepth 1 -type d | sort
}

state_version() {
    local dir=$1 file="$ROOT/state/$(basename "$1").txt"
    [[ -f "$file" ]] && cat "$file" || true
}

cachyos_db() {
    if [[ -n "${CACHYOS_DB:-}" && -s "$CACHYOS_DB" ]]; then
        return 0
    fi
    CACHYOS_DB="${TMPDIR:-/tmp}/cachyos-extra-v3.db"
    export CACHYOS_DB
    if [[ ! -s "$CACHYOS_DB" ]]; then
        curl -fsSL --retry 3 --connect-timeout 15 --max-time 120 \
            "https://mirror.cachyos.org/repo/x86_64_v3/cachyos-extra-v3/cachyos-extra-v3.db" \
            -o "$CACHYOS_DB"
    fi
}

cachyos_version() {
    local pkg=$1 work desc name ver
    cachyos_db || return 1
    work="$(mktemp -d)"
    bsdtar -xf "$CACHYOS_DB" -C "$work" 2>/dev/null || { rm -rf "$work"; return 1; }
    ver=""
    for desc in "$work"/*/desc; do
        [[ -f "$desc" ]] || continue
        name="$(awk -F'%' '/^%NAME%$/{getline; print; exit}' "$desc")"
        if [[ "$name" == "$pkg" ]]; then
            ver="$(awk -F'%' '/^%VERSION%$/{getline; print; exit}' "$desc")"
            break
        fi
    done
    rm -rf "$work"
    [[ -n "$ver" ]] || return 1
    printf '%s\n' "$ver"
}

aur_version() {
    local pkg=$1
    curl -fsSL --retry 3 --connect-timeout 15 --max-time 60 \
        "https://aur.archlinux.org/rpc/v5/info?arg[]=$pkg" \
        | jq -r --arg p "$pkg" '.results[] | select(.Name == $p) | .Version' \
        | head -1
}

# Print the version this repository would build right now for a package dir.
desired_version() {
    local ver base rel our_rel
    case "${TRACK:-}" in
        cachyos)
            ver="$(cachyos_version "$UPSTREAM")" || return 1
            [[ -n "$ver" ]] || return 1
            base="${ver%-*}"
            rel="${ver##*-}"
            our_rel="$(awk -v r="$rel" 'BEGIN { printf "%.1f", r + 0.1 }')"
            printf '%s-%s\n' "$base" "$our_rel"
            ;;
        aur)
            aur_version "$UPSTREAM"
            ;;
        *)
            die "unknown TRACK '$TRACK' in $(basename "$PWD")/meta.sh"
            ;;
    esac
}

# GitHub artifacts and release assets cannot contain ':'; the epoch separator
# is the only realistic offender. repo-add records the actual filename, so
# renaming the archive is safe (the package's internal pkgver keeps the epoch).
sanitize_pkg_names() {
    local dir=$1 f new
    shopt -s nullglob
    for f in "$dir"/*.pkg.tar.zst; do
        new="${f//:/_}"
        [[ "$f" == "$new" ]] || mv -f "$f" "$new"
    done
}
