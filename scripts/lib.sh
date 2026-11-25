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

_state_line() {
    local file="$ROOT/state/$(basename "$1").txt"
    [[ -f "$file" ]] && head -1 "$file" || true
}

state_version() {
    local line
    line="$(_state_line "$1")"
    [[ -n "$line" ]] && awk '{print $1}' <<<"$line" || true
}

state_upstream() {
    local line
    line="$(_state_line "$1")"
    [[ -n "$line" ]] && awk '{print $2}' <<<"$line" || true
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

archrepo_version() {
    local pkg=$1 repo=${ARCH_REPO:-extra}
    curl -fsSL --retry 3 --connect-timeout 15 --max-time 60 \
        "https://archlinux.org/packages/$repo/x86_64/$pkg/json/" \
        | jq -r '"\(.pkgver)-\(.pkgrel)"'
}

newest_version() {
    printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1
}

aur_version() {
    local pkg=$1
    curl -fsSL --retry 3 --connect-timeout 15 --max-time 60 \
        "https://aur.archlinux.org/rpc/v5/info?arg[]=$pkg" \
        | jq -r --arg p "$pkg" '.results[] | select(.Name == $p) | .Version' \
        | head -1
}

# Print the version this repository would build right now for a package dir.
# The CachyOS repository set is authoritative because pacman gives it priority;
# Arch versions are only used as a floor so the overlay still supersedes them.
desired_version() {
    local dir="${1:-}" ver base rel our_rel prev prev_base prev_rel
    local floor base_plus prev_plus arch arel
    case "${TRACK:-}" in
        cachyos)
            ver="$(cachyos_version "$UPSTREAM")" || return 1
            [[ -n "$ver" ]] || return 1
            base="${ver%-*}"
            rel="${ver##*-}"
            floor="$rel"
            arch="$(archrepo_version "$UPSTREAM" || true)"
            if [[ -n "$arch" ]]; then
                arel="${arch##*-}"
                floor="$(newest_version "$rel" "$arel")"
            fi
            base_plus="$(awk -v r="$floor" 'BEGIN { printf "%.1f", r + 0.1 }')"
            our_rel="$base_plus"
            prev="$(state_version "$dir")"
            if [[ -n "$prev" ]]; then
                prev_base="${prev%-*}"
                prev_rel="${prev##*-}"
                if [[ "$prev_base" == "$base" ]]; then
                    prev_plus="$(awk -v r="$prev_rel" 'BEGIN { printf "%.1f", r + 0.1 }')"
                    our_rel="$(newest_version "$base_plus" "$prev_plus")"
                fi
            fi
            printf '%s-%s\n' "$base" "$our_rel"
            ;;
        aur)
            ver="$(aur_version "$UPSTREAM")"
            [[ -n "$ver" ]] || return 1
            printf '%s\n' "$ver"
            ;;
        *)
            die "unknown TRACK '$TRACK' in $(basename "$PWD")/meta.sh"
            ;;
    esac
}

desired_upstream() {
    case "${TRACK:-}" in
        cachyos) cachyos_version "$UPSTREAM" ;;
        aur) aur_version "$UPSTREAM" ;;
        *) return 1 ;;
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
