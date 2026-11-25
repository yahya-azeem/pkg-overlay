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
| `hyprland` | CachyOS + Arch PKGBUILD | Rebuilt with the `no_screen_share` omission patch, linked against the CachyOS repo set. `pkgrel` is above CachyOS and Arch so it wins upgrades. |
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

Or let the helper insert the block (it makes a timestamped backup first):

```sh
sudo ./contrib/install-overlay.sh
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

### Upgrading

Always use a full upgrade, never `pacman -Sy` followed by `pacman -S`:

```sh
sudo pacman -Syu
```

That one rule prevents the hyprgraphics/hyprlock soname mismatch. The overlay
package is versioned as `max(CachyOS pkgrel, Arch pkgrel) + 0.1`, so it is
always newer than both repos and a normal `-Syu` keeps the patched Hyprland
while upgrading `hyprgraphics`, `hyprlock`, `hyprtoolkit` and friends in the
same transaction.

The overlay Hyprland is linked against the **CachyOS** repository set, because
pacman gives the first repo priority and CachyOS's Hypr stack is built as one
unit. Arch's newer `hyprgraphics`/`hyprlock` are only used as a version floor;
the package never forces them ahead of CachyOS. Do not install with `pacman -S`
after only `pacman -Sy`; that is a partial upgrade and can break the stack.

No `IgnorePkg` is needed. The only exposure is a brand-new upstream release
before the CI rebuild lands: during that window `-Syu` can take the stock
package, and the next `-Syu` after CI finishes restores the patched one.

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
   `cachyos/cachyos:latest`. The Hypr stack (`hyprgraphics`, `hyprutils`,
   `hyprlang`, `hyprcursor`, `hyprwire`, `aquamarine`, `hyprtoolkit`,
   `hyprland-guiutils`) is installed explicitly from `cachyos-extra-v3`, so
   Hyprland links the same sonames the target CachyOS system uses. Build tools
   still come from the normal repos, avoiding base-image toolchain downgrades.
   Hyprland is built with the
   `x86_64_v3` devtools profile (`-march=x86-64-v3`, LTO, zstd ultra-20) and
   the patch is verified to be compiled into the binary.
3. **publish** adds every artifact to `pkg-overlay.db.tar.zst`, uploads the
   packages and database to the rolling `pkg-repo` release, and commits the
   new versions to `state/`.

If the Hyprland patch stops applying to a new release, the build fails and the
previous package stays published; the failure is visible in the Actions run.

`state/<package>.txt` records the last published version. If it matches the
upstream version, `detect` skips the build entirely. The first run builds
everything; Hyprland takes roughly 18 minutes.

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

MATLAB (`matlab-mpm`) is published from the private
`github.com/yahya-azeem/pkg-overlay-private` repository because its license
does not allow public redistribution. Fetch it with the authenticated `gh`
CLI and serve it from a local file repository:

```sh
gh repo clone yahya-azeem/pkg-overlay-private
~/pkg-overlay-private/fetch.sh
```

See that repository's README for the `pacman.conf` block. GitHub release
assets cannot contain `:`, so the MATLAB archive is published as
`matlab-mpm-1_...`; the package's internal epoch is unchanged and `repo-add`
records the real filename.

## Manual build

The same scripts run outside GitHub Actions on CachyOS:

```sh
sudo pacman -S --needed base-devel git
./scripts/ci-build.sh hyprland      # root is needed for dependency install
./scripts/publish.sh                # needs gh auth + write access
```
