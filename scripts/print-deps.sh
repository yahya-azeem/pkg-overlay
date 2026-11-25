#!/usr/bin/env bash
# Print the pacman dependencies of one package directory.
set -Eeuo pipefail

source "$(dirname -- "$0")/lib.sh"

dir="${1:?usage: print-deps.sh <package-dir>}"
[[ -d "$dir" ]] || dir="$ROOT/packages/$dir"
dir="$(cd "$dir" && pwd)"

(
    unset TRACK UPSTREAM BUILD
    source "$dir/meta.sh"
    case "${BUILD:-aur}" in
        custom)
            exec "$dir/build.sh" --print-deps
            ;;
        aur)
            cd "$dir"
            bash -c 'set +u; source ./PKGBUILD >/dev/null 2>&1; printf "%s\n" "${depends[@]}" "${makedepends[@]}"'
            ;;
        *)
            die "unknown BUILD '$BUILD' in $dir/meta.sh"
            ;;
    esac
) | sort -u
