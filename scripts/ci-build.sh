#!/usr/bin/env bash
# Build one package inside the CachyOS CI container.
# Runs as root; makepkg runs as the unprivileged "builder" user.
set -Eeuo pipefail

source "$(dirname -- "$0")/lib.sh"

dir="${1:?usage: ci-build.sh <package-dir>}"
[[ -d "$dir" ]] || dir="$ROOT/packages/$dir"
dir="$(cd "$dir" && pwd)"
name="$(basename "$dir")"
out="$ROOT/out/$name"
mkdir -p "$out"

is_root=0
[[ $EUID -eq 0 ]] && is_root=1

if (( is_root )); then
    pacman -S --needed --noconfirm base-devel git curl unzip jq >/dev/null
    id builder >/dev/null 2>&1 || useradd -m builder
    chown -R builder: "$ROOT"
fi

deps_file="$(mktemp)"
if (( is_root )); then
    runuser -u builder -- "$ROOT/scripts/print-deps.sh" "$dir" > "$deps_file"
else
    "$ROOT/scripts/print-deps.sh" "$dir" > "$deps_file"
fi
mapfile -t deps < "$deps_file"
rm -f "$deps_file"

if (( ${#deps[@]} )); then
    log "$name: installing ${#deps[@]} dependencies"
    if (( is_root )); then
        pacman -S --needed --noconfirm "${deps[@]}"
    else
        warn "not root; assuming build dependencies are installed: ${deps[*]}"
    fi
fi

# Package-specific pinning runs after dependency installation, because a
# later `pacman -S --needed` would otherwise upgrade pinned libraries.
if [[ -x "$dir/pin.sh" ]]; then
    log "$name: pinning package-specific library versions"
    if (( is_root )); then
        "$dir/pin.sh"
    else
        warn "not root; skipping $name/pin.sh"
    fi
fi

log "$name: building into $out"
if (( is_root )); then
    runuser -u builder -- env OUT="$out" "$ROOT/scripts/build-one.sh" "$dir"
else
    OUT="$out" "$ROOT/scripts/build-one.sh" "$dir"
fi
