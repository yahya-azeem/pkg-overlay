#!/usr/bin/env bash
# Build an AUR package from the current AUR snapshot.
# The snapshot is fetched fresh so CI always builds the version AUR reports;
# the repo copy of PKGBUILD is updated to match what was built.
set -Eeuo pipefail

source "$(dirname -- "$0")/lib.sh"

dir="${1:?usage: build-aur.sh <package-dir> <out>}"
out="${2:?usage: build-aur.sh <package-dir> <out>}"
mkdir -p "$out"

unset TRACK UPSTREAM BUILD
source "$dir/meta.sh"
: "${UPSTREAM:?UPSTREAM must be set in meta.sh}"

work="$out/aur-src"
rm -rf "$work"
mkdir -p "$work"

log "fetching AUR snapshot for $UPSTREAM"
curl -fsSL --retry 3 --connect-timeout 15 --max-time 120 \
    "https://aur.archlinux.org/cgit/aur.git/snapshot/${UPSTREAM}.tar.gz" \
    | tar -xz -C "$work"

src="$work/$UPSTREAM"
[[ -d "$src" ]] || die "AUR snapshot did not contain $UPSTREAM"

# Keep the committed recipe in sync before makepkg pollutes the tree with
# downloaded source archives.
cp -f "$src/PKGBUILD" "$dir/PKGBUILD"
find "$src" -maxdepth 1 -type f \
    ! -name PKGBUILD ! -name .SRCINFO ! -name '*.tar.*' \
    -exec cp -f {} "$dir/" \;

cd "$src"
rm -f "$out"/*.pkg.tar.zst
export PKGDEST="$out"
log "building $UPSTREAM from the AUR snapshot"
makepkg -f --noconfirm --nodeps

mapfile -t built < <(compgen -G "$out/*.pkg.tar.zst" | grep -v -- '-debug-' | sort)
(( ${#built[@]} )) || die "makepkg produced no package for $UPSTREAM"
rm -f "$out"/*-debug-*.pkg.tar.zst

version=""
for pkgfile in "${built[@]}"; do
    info="$(bsdtar -xOf "$pkgfile" .PKGINFO)"
    pkgname="$(awk -F' = ' '/^pkgname/{print $2; exit}' <<<"$info")"
    if [[ "$pkgname" == "$UPSTREAM" ]]; then
        version="$(awk -F' = ' '/^pkgver/{print $2; exit}' <<<"$info")"
        break
    fi
done
[[ -n "$version" ]] || version="$(bsdtar -xOf "${built[0]}" .PKGINFO | awk -F' = ' '/^pkgver/{print $2; exit}')"
[[ -n "$version" ]] || die "could not read the built version"
printf '%s\n' "$version" > "$out/VERSION"

rm -rf "$work"
log "$UPSTREAM $version built"
