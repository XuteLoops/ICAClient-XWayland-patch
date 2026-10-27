# Citrix Workspace for Wayland with XWayland

Tooling for running the Linux Citrix Workspace client through XWayland on
Wayland desktops. The tracked repository does **not** contain Citrix software.
It builds from an official package you supply, or patches an installation that
is already on the system.

Use it to:

- Build a portable AppImage from an official Citrix `.deb`, `.rpm`, or tarball.
- Patch an existing `/opt/Citrix/ICAClient` (or custom) installation in place.
- Bundle the WebKitGTK runtime used by the Citrix UI.
- Optionally include USB redirection from a Citrix USB package.
- Keep the client on the X11 GDK backend so it runs through XWayland.

The project is not affiliated with or endorsed by Citrix.

## Requirements

### Build requirements

- x86_64 Linux. Building in WSL is supported.
- Bash, Python 3, `tar`, `curl`, `file`, and standard GNU utilities.
- For `.deb`: `dpkg-deb`, or `ar` plus a `tar` that supports the payload
  compression.
- For `.rpm`: `bsdtar`, or `rpm2cpio` plus `cpio`.
- For tarballs: `tar`; the official Citrix tarball also uses its bundled
  `setupwfc` installer.
- `appimagetool` is downloaded automatically and cached in
  `~/.cache/appimagetool`.

### Runtime requirements

- FUSE for running an AppImage directly. If FUSE is unavailable, use
  `--appimage-extract-and-run`.
- The usual Citrix client runtime libraries for your distribution. The AppImage
  bundles a selected set of Ubuntu 22.04 compatibility libraries, but it does not
  replace every host dependency.
- `sudo` for installing system USB redirection.
- An X11 or XWayland display.

## Build from an official package

Download the Citrix Workspace package from Citrix. Then run:

```bash
chmod +x patch-citrix.sh
./patch-citrix.sh build --package ~/Downloads/icaclient-gcc-8_26.04.10.1_amd64.deb
```

The AppImage is written to:

```text
dist/Citrix_Workspace_<version>-x86_64.AppImage
```

The version is taken from the package filename when possible, otherwise it is
`patched`.

### Package formats

```bash
./patch-citrix.sh build --package ~/Downloads/icaclient-*.deb
./patch-citrix.sh build --package ~/Downloads/icaclient-*.rpm
./patch-citrix.sh build --package ~/Downloads/linuxx64-*.tar.gz
```

The official tarball is an installer archive, not a ready-made client tree.
When `setupwfc` is present, the build script runs it into a temporary prefix.

If the tarball installer changes its prompts and noninteractive installation
fails:

1. Run the Citrix installer normally and choose an installation directory.
2. Patch that installation with the existing-installation flow below.
3. Keep the installed tree; it is the copy that will be used and modified.

### Optional USB package

A Citrix USB package can be merged while building:

```bash
./patch-citrix.sh build \
    --package ~/Downloads/icaclient-gcc-8_26.04.10.1_amd64.deb \
    --usb ~/Downloads/ctxusb-gcc-8_26.04.10.1_amd64.deb
```

If a `ctxusb*.deb`, `ctxusb*.rpm`, or `ctxusb*.tar.*` file is next to the client
package or in the current directory, it is detected automatically. Use
`--no-usb` to skip USB support.

Including the USB payload does not install it into the system automatically.
Install it later with the launcher’s `--install-usb` flag.

### Build options

```text
--package PATH     Citrix client package (.deb, .rpm, or .tar.*)
--usb PATH         Optional Citrix USB package
--no-usb           Do not merge a USB package
--out PATH         Output AppImage path
--work DIR         Work directory
--version VERSION  Version used in the output filename
--no-fetch         Do not download Ubuntu runtime libraries
```

`--no-fetch` is useful offline, but the AppImage may then be missing libraries
that are bundled by the normal build. Those libraries must be present on the
target system.

## Patch an existing installation

Use this when Citrix Workspace is already installed:

```bash
sudo ./patch-citrix.sh existing --icaroot /opt/Citrix/ICAClient
```

For a custom installation directory, pass that directory instead of
`/opt/Citrix/ICAClient`.

The existing flow:

- Verifies `selfservice` and `wfica` are present.
- Extracts the bundled WebKit runtime when needed.
- Applies the WebKit relocation patch.
- Enables `GenericUSB` in `config/module.ini`.
- Restores the EULA and configuration files required by the client.
- Installs a launcher at `<ICAROOT>/citrix-workspace`.

Original files are saved under `<ICAROOT>/.citrix-wayland-backup`. Use
`--no-backup` to skip the backup. There is no automatic restore command; the
backup directory is kept so it can be restored manually.

### Existing installation with USB

```bash
sudo ./patch-citrix.sh existing \
    --icaroot /opt/Citrix/ICAClient \
    --usb ~/Downloads/ctxusb-gcc-8_26.04.10.1_amd64.deb
```

To install USB support immediately:

```bash
sudo ./patch-citrix.sh existing \
    --icaroot /opt/Citrix/ICAClient \
    --usb ~/Downloads/ctxusb-gcc-8_26.04.10.1_amd64.deb \
    --install-usb
```

Without `--usb`, an existing installation must already contain the USB helper
files and udev rules if `--install-usb` is used.

### Existing installation options

```text
--icaroot PATH     Directory containing selfservice and wfica
--usb PATH         Optional Citrix USB package to merge
--install-usb      Install the USB daemon and udev rules after patching
--work DIR         Work directory
--no-backup        Do not save originals under .citrix-wayland-backup
```

If the existing installation is writable by your user, the patch can be run
without `sudo`, but system USB installation still needs root.

## Running

### AppImage

```bash
chmod +x dist/Citrix_Workspace_*.AppImage
./dist/Citrix_Workspace_*.AppImage
```

Common modes:

```bash
./Citrix_Workspace_*.AppImage --selfservice
./Citrix_Workspace_*.AppImage --configmgr
./Citrix_Workspace_*.AppImage --conncenter
./Citrix_Workspace_*.AppImage --wfica /path/to/session.ica
./Citrix_Workspace_*.AppImage --new-store
./Citrix_Workspace_*.AppImage --install-usb
./Citrix_Workspace_*.AppImage --diagnose
./Citrix_Workspace_*.AppImage --integrate
```

Desktop integration is installed automatically on the first GUI launch. Set
`CITRIX_APPIMAGE_NO_INTEGRATE=1` to disable it, or run `--integrate` manually.

### Existing installation

```bash
/opt/Citrix/ICAClient/citrix-workspace
/opt/Citrix/ICAClient/citrix-workspace --configmgr
/opt/Citrix/ICAClient/citrix-workspace --install-usb
/opt/Citrix/ICAClient/citrix-workspace --diagnose
```

To put the launcher on `PATH`:

```bash
sudo ln -s /opt/Citrix/ICAClient/citrix-workspace /usr/local/bin/citrix-workspace
```

The existing-installation launcher does not install desktop entries or MIME
associations automatically.

## Launcher flags

| Flag | AppImage | Existing | Description |
| --- | --- | --- | --- |
| `--selfservice` | yes | yes | Start Citrix Workspace |
| `--receiver` | yes | yes | Start the receiver helper |
| `--configmgr` | yes | yes | Start the configuration manager |
| `--conncenter` | yes | yes | Start the connection center |
| `--wfica` | yes | yes | Start the ICA engine |
| `--new-store` | yes | yes | Add a new store |
| `--install-usb` | yes | yes | Install USB daemon, rules, and helper permissions |
| `--diagnose` | yes | yes | Print diagnostic information |
| `--integrate` | yes | no | Install desktop entries and MIME associations |

The client is forced onto the X11 backend with `GDK_BACKEND=x11`, which makes
it use XWayland. To experiment with the Wayland backend:

```bash
CITRIX_GDK_BACKEND=wayland ./Citrix_Workspace_*.AppImage
```

## How it works

The build flow:

1. Extracts the supplied package into a clean work directory.
2. Locates the directory containing `selfservice` and `wfica`.
3. Runs the official `setupwfc` installer when the package is an installer
   archive rather than a filesystem tree.
4. Merges an optional USB package.
5. Extracts the bundled WebKitGTK 4.0 runtime.
6. Patches the WebKit helper path from an absolute path to a relocatable path.
7. Bundles the selected Ubuntu compatibility libraries for the AppImage.
8. Prepares `module.ini`, EULA files, and templates.
9. Installs the launcher, diagnostic helper, USB helper, and desktop metadata.
10. Packages the result as an AppImage.

The existing-installation flow performs the same WebKit and configuration
steps in place, without building an AppImage.

The WebKit patch changes:

```text
/usr/lib/x86_64-linux-gnu/webkit2gtk-4.0
```

to the same-length relative path:

```text
usr//lib/x86_64-linux-gnu/webkit2gtk-4.0
```

The double slash is intentional: it preserves the binary length of the
original string.

## USB redirection

USB support has two parts:

1. The Citrix USB payload (`ctxusbd`, `ctxusb`, `ctx_usb_isactive`, libraries,
   configuration, and udev rules) must be merged with `--usb` or already be in
   the installation.
2. The system integration must be installed with `--install-usb`.

The installer writes:

- `ctxusb` as a setuid helper under the client root.
- `ctxusbd.service` under `/etc/systemd/system`.
- Citrix udev rules under `/etc/udev/rules.d`.
- `ICAROOT` in the USB daemon environment.

The AppImage and existing-installation launchers both pass
`CITRIX_USB_ICAROOT`, so USB support is installed relative to the client that
was actually patched.

After installation, reconnect USB devices or log out and back in.

## Diagnostics

Run the diagnostic helper:

```bash
./Citrix_Workspace_*.AppImage --diagnose
/opt/Citrix/ICAClient/citrix-workspace --diagnose
```

It reports:

- The detected client root and library directory.
- X11/XWayland availability.
- Bundled libraries and WebKit helpers.
- WebKit relocation patch state.
- Unresolved dynamic libraries.
- `GenericUSB` and EULA state.
- Desktop integration and USB service state.

## Packaging native and Flatpak outputs

The packaging helper consumes a locally built AppImage:

```bash
VERSION=26.04.10.1 packaging/build-packages.sh deb
VERSION=26.04.10.1 packaging/build-packages.sh rpm
VERSION=26.04.10.1 packaging/build-packages.sh arch
VERSION=26.04.10.1 packaging/build-packages.sh flatpak
```

With no format argument it builds `deb`, `rpm`, `arch`, and `flatpak`.

These outputs embed the Citrix client. They are for local testing only and must
not be redistributed without permission from Citrix.

The Flatpak build requires `flatpak` and `flatpak-builder`. In WSL, GUI testing
may need:

```bash
dbus-run-session -- flatpak run io.github.citrixworkspace.CitrixWorkspace
```

## Troubleshooting

### `file` is missing

`appimagetool` requires the `file` command. Install it with your distribution’s
package manager, then rerun the build.

### `appimagetool` or runtime download fails

The build downloads `appimagetool` and the AppImage runtime from GitHub. Check
network access. Temporary downloads are stored under `~/.cache`.

### The AppImage does not start because FUSE is unavailable

Use the AppImage extraction fallback:

```bash
./Citrix_Workspace_*.AppImage --appimage-extract-and-run
```

### The tarball installer fails

The official Citrix tarball is interactive. If the noninteractive answers do
not match the current installer, install Citrix normally with `setupwfc`, then
patch that installation:

```bash
sudo ./patch-citrix.sh existing --icaroot <installed-client-root>
```

### Missing libraries

The AppImage bundles a subset of Ubuntu 22.04 libraries. If the client reports a
missing shared object, install the corresponding runtime package for your
distribution. Build without `--no-fetch` to include the normal compatibility
set.

### WebKit or blank window

The launcher sets:

```text
WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1
```

This is required because the bundled WebKit helper is launched from a
relocatable prefix. It reduces WebKit sandbox protection; keep the client
updated and treat untrusted ICA content accordingly.

### USB devices are not detected

1. Confirm `ctxusbd` exists in the client root.
2. Confirm the USB package was merged with `--usb`.
3. Run `--install-usb` as root.
4. Reconnect the device or log out and back in.
5. Check `systemctl status ctxusbd.service`.

### EULA files are missing

The client requires both `<ICAROOT>/eula.txt` and
`<ICAROOT>/config/eula.txt`. The patcher restores them from the packaged
`nls/en.UTF-8` directory when available.

## Repository layout

```text
patch-citrix.sh                 Top-level build/existing CLI
build-from-source.sh            Retired compatibility shim
appimage/
  common.sh                     Package extraction and patch helpers
  build-appimage.sh             AppImage builder
  patch-existing.sh             Existing-installation patcher
  run-existing.sh               Existing-installation launcher
  AppRun                        AppImage launcher
  install-usb.sh                USB system integration
  diagnose.sh                   Diagnostics
  integrate.sh                  AppImage desktop integration
  patch_webkit.py               WebKit helper-path patch
  patch_module_ini.py           GenericUSB configuration patch
  relativize_symlinks.py        AppImage symlink relocation
  fetch_jammy_libs.py           Ubuntu compatibility-library fetcher
packaging/
  build-packages.sh             Local deb/rpm/Arch/Flatpak builder
  files/                        Native and Flatpak packaging files
```

The local `local/` directory and the `dist/` build output are ignored. They can
contain copies of the proprietary Citrix client; do not publish them, and delete
`local/` before archiving the project folder if it is no longer needed.

## Licensing

Citrix Workspace is proprietary software. This repository does not grant a
license to Citrix software, and building or patching it does not grant
redistribution rights. Obtain the client from Citrix and follow the applicable
Citrix license terms.

Built AppImages, native packages, and Flatpak bundles contain Citrix files. Keep
them local unless Citrix has explicitly authorized redistribution.
