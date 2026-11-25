#!/usr/bin/env bash
# Add the pkg-overlay repository to pacman.conf, above CachyOS.
# Run with sudo. A timestamped backup is made first.
set -Eeuo pipefail

[[ $EUID -eq 0 ]] || { echo "run with sudo: sudo $0" >&2; exit 1; }

conf=/etc/pacman.conf
backup="$conf.bak.$(date +%Y%m%d-%H%M%S)"
cp -a "$conf" "$backup"
echo "backup: $backup"

if grep -q '^\[pkg-overlay\]' "$conf"; then
    echo "pkg-overlay is already configured"
    exit 0
fi

python3 - "$conf" <<'PY'
import sys

path = sys.argv[1]
lines = open(path).read().splitlines()

insert = None
for i, line in enumerate(lines):
    stripped = line.strip()
    if stripped.startswith("[") and stripped.endswith("]") and stripped != "[options]":
        insert = i
        break

if insert is None:
    raise SystemExit("could not find a repository section in pacman.conf")

block = [
    "[pkg-overlay]",
    "SigLevel = Optional TrustAll",
    "Server = https://github.com/yahya-azeem/pkg-overlay/releases/download/pkg-repo",
    "",
]
lines[insert:insert] = block

with open(path, "w") as fh:
    fh.write("\n".join(lines) + "\n")
PY

echo "pkg-overlay added above the first repository"
pacman -Sy
