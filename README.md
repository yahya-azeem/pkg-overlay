# pkg-overlay

A small pacman repository for packages I maintain or patch, built in GitHub
Actions. Most of the system still comes from CachyOS; this repo only supplies
the packages listed below.

- **Repository:** <https://github.com/yahya-azeem/pkg-overlay>
- **Release (pacman `Server`):** <https://github.com/yahya-azeem/pkg-overlay/releases/download/pkg-repo>
- **Database:** `pkg-overlay.db.tar.zst`

## Packages

| Package | Source | Notes |
|---|---|---|
| `hyprland` | CachyOS + Arch PKGBUILD | Rebuilt with the `no_screen_share` omission patch. `pkgrel` is one higher than CachyOS so it replaces the stock package. |
| `hyprpm` | same build | Built alongside Hyprland. |
| `arduino-ide-bin` | AUR | Repack of the official Arduino IDE 2 release. |
| `vinegar` | AUR | Roblox bootstrapper. |

Packages that cannot be redistributed publicly (for example MATLAB's `mpm`)
are built in a separate private repository and are not published here.

## Use it

Add this **above** the CachyOS repositories in `/etc/pacman.conf`:

```ini
[pkg-overlay]
SigLevel = Optional TrustAll
Server = https://github.com/yahya-azeem/pkg-overlay/releases/download/pkg-repo
```

Then:

```sh
sudo pacman -Sy
sudo pacman -S hyprland          # picks the patched build
sudo pacman -S arduino-ide-bin
```

`SigLevel = Optional TrustAll` is used because the packages are not signed;
they are built from public recipes by GitHub Actions and published to this
repository's release assets.

### Keeping the patched Hyprland

When CachyOS bumps Hyprland, this repo rebuilds it with the patch on the next
scheduled run (four times a day). Between the CachyOS update and that rebuild,
a `pacman -Syu` can replace the patched package with the stock one. Hold it:

```ini
# /etc/pacman.conf
IgnorePkg = hyprland hyprpm
```

With the hold, `pacman -Syu` keeps your patched build; install the rebuilt
package manually when it appears:

```sh
sudo pacman -Syu --ignore hyprland,hyprpm
sudo pacman -U ~/Downloads/hyprland-*.pkg.tar.zst
```

Or temporarily drop the hold, upgrade, and reinstall the overlay package.

## How the build works

```
packages/<name>/meta.sh     TRACK=cachyos|aur, UPSTREAM=<pkg>, BUILD=custom|aur
packages/hyprland/          patch + PKGBUILD generator + v3 build flags
packages/<name>/PKGBUILD    AUR recipe (refreshed from the AUR at build time)
scripts/detect.sh           compares upstream versions with state/
scripts/ci-build.sh         builds one package in the CachyOS container
scripts/publish.sh          repo-add + GitHub release upload + state commit
state/<name>.txt            version that was last published
```

`.github/workflows/build.yml` runs on a schedule and on pushes:

1. **detect** reads the CachyOS database and the AUR RPC API and compares
   versions with `state/`. Only changed packages are built.
2. **build** runs one matrix job per changed package in
   `cachyos/cachyos:latest`, with the `cachyos-*-v3` repositories enabled, so
   dependencies match what CachyOS ships. Hyprland is built with the
   `x86_64_v3` devtools profile (`-march=x86-64-v3`, LTO, zstd ultra-20) and
   the patch is verified to be compiled into the binary.
3. **publish** adds every artifact to `pkg-overlay.db.tar.zst`, uploads the
   packages and database to the rolling `pkg-repo` release, and commits the
   new versions to `state/`.

If the Hyprland patch stops applying to a new release, the build fails and the
previous package stays published; the failure is visible in the Actions run.

## Add another package

For an AUR package:

```sh
mkdir -p packages/<pkg>
printf 'TRACK=aur\nUPSTREAM=<pkg>\nBUILD=aur\n' > packages/<pkg>/meta.sh
curl -fsSL "https://aur.archlinux.org/cgit/aur.git/snapshot/<pkg>.tar.gz" |
    tar -xz -C packages/<pkg> --strip-components=1
```

Commit it. The next run builds it and adds it to the repository.

For a package that needs its own recipe/patch, use `BUILD=custom` and provide
`packages/<pkg>/build.sh` accepting `--print-deps` and an output directory,
like `packages/hyprland/build.sh`.

## Private packages

MATLAB (`matlab-mpm`) is published from
`github.com/yahya-azeem/pkg-overlay-private` because its license does not
allow public redistribution. Fetch it with `gh` and install locally; see that
repository's README.

## Manual build

The same scripts run outside GitHub Actions on CachyOS:

```sh
sudo pacman -S --needed base-devel git
./scripts/ci-build.sh hyprland      # root is needed for dependency install
./scripts/publish.sh                # needs gh auth + write access
```
