#!/usr/bin/env bash
# Build Hyprland from the Arch PKGBUILD that CachyOS uses, with the
# no_screen_share omission patch applied.
#
# The build environment must give the CachyOS repositories priority, exactly
# like the target machine; otherwise the package links against Arch sonames
# that CachyOS has not rebuilt yet.
#
# Usage:
#   build.sh --print-deps     print build dependencies (PKGBUILD generated)
#   build.sh <outdir>         build; packages + VERSION are written to <outdir>
set -Eeuo pipefail

DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$DIR/../.." && pwd)"
PATCH="$DIR/noscreenshare-omit.patch"
CONF="$DIR/makepkg-v3.conf"

# shellcheck source=../../scripts/lib.sh
source "$ROOT/scripts/lib.sh"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m==>\033[0m %s\n' "$*" >&2; exit 1; }

# CachyOS's version is the one pacman actually selects (repo priority).
cachyos_version() {
    pacman -Si hyprland | awk -F': *' '
        /^Repository/ { repo = $2 }
        /^Version/    { if (repo ~ /^cachyos/) { print $2; exit } }
    '
}

extra_version() {
    pacman -Si hyprland | awk -F': *' '
        /^Repository/ { repo = $2 }
        /^Version/    { if (repo == "extra") { print $2; exit } }
    '
}

generate_pkgbuild() {
    local ver base rel floor our_rel prev prev_base prev_rel arch arel tag url tmp patch_sha
    local base_plus prev_plus

    ver="$(cachyos_version)"
    [[ -n "$ver" ]] || die "cannot read CachyOS hyprland version with pacman"

    base="${ver%-*}"
    rel="${ver##*-}"
    floor="$rel"

    # Arch's pkgrel is only a version floor; dependencies come from the
    # CachyOS repos because pacman gives them priority on the target system.
    arch="$(extra_version || true)"
    if [[ -n "$arch" ]]; then
        arel="${arch##*-}"
        floor="$(newest_version "$rel" "$arel")"
    fi
    base_plus="$(awk -v r="$floor" 'BEGIN { printf "%.1f", r + 0.1 }')"
    our_rel="$base_plus"

    # Keep the published pkgrel monotonic when a rebuild is triggered by a
    # dependency/toolchain change rather than an upstream version change.
    prev="$(awk 'NR==1 { print $1 }' "$ROOT/state/hyprland.txt" 2>/dev/null || true)"
    if [[ -n "$prev" ]]; then
        prev_base="${prev%-*}"
        prev_rel="${prev##*-}"
        if [[ "$prev_base" == "$base" ]]; then
            prev_plus="$(awk -v r="$prev_rel" 'BEGIN { printf "%.1f", r + 0.1 }')"
            our_rel="$(newest_version "$base_plus" "$prev_plus")"
        fi
    fi

    # Arch packaging tag for the CachyOS release we are tracking.
    tag="$base-${rel%%.*}"
    url="https://gitlab.archlinux.org/archlinux/packaging/packages/hyprland/-/raw/$tag/PKGBUILD"
    log "fetching Arch PKGBUILD $tag" >&2
    tmp="$(mktemp)"
    curl -fsSL --retry 3 --connect-timeout 15 --max-time 60 "$url" -o "$tmp" \
        || die "could not download $url"

    grep -qx "pkgver=$base" "$tmp" || die "PKGBUILD does not declare pkgver=$base"
    grep -qx "pkgrel=${rel%%.*}" "$tmp" || die "PKGBUILD does not declare pkgrel=${rel%%.*}"

    patch_sha="$(sha256sum "$PATCH" | awk '{print $1}')"

    python3 - "$tmp" "$our_rel" "$patch_sha" <<'PYEOF'
import pathlib
import re
import sys

pkgbuild = pathlib.Path(sys.argv[1])
our_rel, patch_sha = sys.argv[2], sys.argv[3]
s = pkgbuild.read_text()

s, n = re.subn(r"(?m)^pkgrel=\d+(?:\.\d+)?$", f"pkgrel={our_rel}", s, count=1)
assert n == 1, "pkgrel line not found"

m = re.search(r"(?m)^arch=\((.*)\)$", s)
assert m, "arch=() line not found"
if "x86_64_v3" not in m.group(1).split():
    s = s[:m.start(1)] + m.group(1) + " x86_64_v3" + s[m.end(1):]

s = s.replace("source=(", 'source=("noscreenshare-omit.patch"\n        ', 1)
s = s.replace("sha256sums=('", f"sha256sums=('{patch_sha}'\n             '", 1)

anchor = 'cd "$_archive"\n'
assert anchor in s, "unexpected prepare() layout"
s = s.replace(
    anchor,
    anchor + '\tpatch -Np1 -i "$srcdir/noscreenshare-omit.patch"\n',
    1,
)

pkgbuild.write_text(s)
PYEOF

    cp "$tmp" "$DIR/PKGBUILD"
    rm -f "$tmp"
    printf '%s-%s\n' "$base" "$our_rel"
}

if [[ "${1:-}" == "--print-deps" ]]; then
    generate_pkgbuild >/dev/null
    cd "$DIR"
    bash -c 'set +u; source ./PKGBUILD >/dev/null 2>&1; printf "%s\n" "${depends[@]}" "${makedepends[@]}"' \
        | sort -u
    exit 0
fi

out="${1:?usage: build.sh <outdir>}"
cd "$DIR"
mkdir -p "$out"
out="$(cd "$out" && pwd)"

version="$(generate_pkgbuild)"
log "building hyprland $version against CachyOS repo versions"

rm -rf "$DIR/src" "$DIR/pkg"
export PKGDEST="$out"
export SRCDEST="$DIR/src-cache"
export MAKEFLAGS="${MAKEFLAGS:--j$(nproc)}"

makepkg --config "$CONF" -f --nodeps --noconfirm

sanitize_pkg_names "$out"
mapfile -t built < <(compgen -G "$out/hyprland-$version-*.pkg.tar.zst" | grep -v -- '-debug-' | sort)
(( ${#built[@]} == 1 )) || die "expected one hyprland package, found ${#built[@]}"
main_pkg="${built[0]}"

pkginfo="$(bsdtar -xOf "$main_pkg" .PKGINFO)"
grep -qx "pkgver = $version" <<<"$pkginfo" || die "package version mismatch"
pkgarch="$(awk -F' = ' '/^arch/{print $2}' <<<"$pkginfo")"
[[ "$pkgarch" == x86_64_v3 ]] || die "package arch is $pkgarch, expected x86_64_v3"

bin_tmp="$(mktemp)"
bsdtar -xOf "$main_pkg" usr/bin/Hyprland > "$bin_tmp" \
    || die "cannot read usr/bin/Hyprland from package"
if ! grep -aq 'render:no_screen_share_omit' "$bin_tmp"; then
    rm -f "$bin_tmp"
    die "compiled binary does not contain render:no_screen_share_omit"
fi
rm -f "$bin_tmp"

# The package must link the same hyprgraphics soname that CachyOS currently
# ships; otherwise installing it would force Arch's newer library and break
# hyprlock/hyprtoolkit.
gfx_so="$(ls /usr/lib/libhyprgraphics.so.* 2>/dev/null | sed 's/.*\.so\.//' | sort -V | tail -1)"
if [[ -n "$gfx_so" ]] && ! grep -q "libhyprgraphics.so=$gfx_so-64" <<<"$pkginfo"; then
    die "package does not match the installed CachyOS hyprgraphics soname $gfx_so"
fi

# CachyOS does not publish debug packages; keep the release slim.
rm -f "$out"/*-debug-*.pkg.tar.zst
printf '%s\n' "$version" > "$out/VERSION"
printf '%s\n' "$(cachyos_version)" > "$out/UPSTREAM"

log "hyprland $version built ($pkgarch, hyprgraphics soname ${gfx_so:-unknown}, patch=compiled)"
