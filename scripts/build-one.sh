#!/usr/bin/env bash
# Dispatch to the right builder for one package directory.
set -Eeuo pipefail

source "$(dirname -- "$0")/lib.sh"

dir="${1:?usage: build-one.sh <package-dir>}"
out="${OUT:?OUT must be set}"
dir="$(cd "$dir" && pwd)"

unset TRACK UPSTREAM BUILD
source "$dir/meta.sh"

case "${BUILD:-aur}" in
    custom)
        "$dir/build.sh" "$out"
        ;;
    aur)
        "$ROOT/scripts/build-aur.sh" "$dir" "$out"
        ;;
    *)
        die "unknown BUILD '$BUILD' in $dir/meta.sh"
        ;;
esac
