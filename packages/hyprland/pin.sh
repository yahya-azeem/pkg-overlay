#!/usr/bin/env bash
# Downgrade the Hypr stack to the CachyOS builds after dependency installation.
# The container resolves core/extra first, but the target machine gets these
# sonames from the CachyOS repos; linking Arch's newer soname makes the package
# uninstallable alongside CachyOS's hyprlock/hyprtoolkit.
set -Eeuo pipefail

pacman -S --noconfirm \
    cachyos-extra-v3/aquamarine \
    cachyos-extra-v3/hyprcursor \
    cachyos-extra-v3/hyprgraphics \
    cachyos-extra-v3/hyprlang \
    cachyos-extra-v3/hyprutils \
    cachyos-extra-v3/hyprwire \
    cachyos-extra-v3/hyprtoolkit \
    cachyos-extra-v3/hyprland-guiutils \
    cachyos-extra-v3/hyprland-protocols

pacman -Q hyprgraphics hyprtoolkit hyprland-guiutils
ls /usr/lib/libhyprgraphics.so.*
