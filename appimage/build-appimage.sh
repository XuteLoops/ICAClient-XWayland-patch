#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$HERE/.." && pwd)"
# shellcheck source=common.sh
source "$HERE/common.sh"

usage() {
    cat <<EOF
Usage:
  $(basename "$0") --package <client-package> [options]

Build a relocatable AppImage from an official Citrix Workspace package.

Options:
  --package PATH     Citrix package (.deb, .rpm, or .tar.*)
  --usb PATH         Optional Citrix USB package
  --no-usb           Do not merge a USB package
  --out PATH         Output AppImage path
  --work DIR         Work directory
  --version VERSION  Version used in the output filename
  --no-fetch         Do not download Ubuntu runtime libraries
  --help             Show this help
EOF
}

CLIENT_PACKAGE="${CLIENT_PACKAGE:-${ICACLIENT_DEB:-}}"
USB_PACKAGE="${USB_PACKAGE:-${CTXUSB_DEB:-}}"
OUT="${OUT:-}"
WORK="${WORK:-$DEFAULT_WORK}"
VERSION="${VERSION:-}"
FETCH_LIBS=1
AUTO_USB=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --package|--client)
            [[ $# -ge 2 ]] || die "$1 requires a path"
            CLIENT_PACKAGE="$2"
            shift 2
            ;;
        --usb)
            [[ $# -ge 2 ]] || die "--usb requires a path"
            USB_PACKAGE="$2"
            AUTO_USB=0
            shift 2
            ;;
        --no-usb)
            AUTO_USB=0
            USB_PACKAGE=""
            shift
            ;;
        --out)
            [[ $# -ge 2 ]] || die "--out requires a path"
            OUT="$2"
            shift 2
            ;;
        --work)
            [[ $# -ge 2 ]] || die "--work requires a path"
            WORK="$2"
            shift 2
            ;;
        --version)
            [[ $# -ge 2 ]] || die "--version requires a value"
            VERSION="$2"
            shift 2
            ;;
        --no-fetch)
            FETCH_LIBS=0
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            die "unknown argument: $1"
            ;;
    esac
done

[[ -n "$CLIENT_PACKAGE" ]] || { usage; die "--package is required"; }
CLIENT_PACKAGE="$(abs_path "$CLIENT_PACKAGE")"
[[ -f "$CLIENT_PACKAGE" ]] || die "client package not found: $CLIENT_PACKAGE"

if [[ -z "$USB_PACKAGE" && "$AUTO_USB" == "1" ]]; then
    USB_PACKAGE="$(find_usb_next_to "$(dirname "$CLIENT_PACKAGE")" || true)"
fi
if [[ -n "$USB_PACKAGE" ]]; then
    USB_PACKAGE="$(abs_path "$USB_PACKAGE")"
    [[ -f "$USB_PACKAGE" ]] || die "USB package not found: $USB_PACKAGE"
fi

if [[ -z "$VERSION" ]]; then
    if [[ "$(basename "$CLIENT_PACKAGE")" =~ ([0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?) ]]; then
        VERSION="${BASH_REMATCH[1]}"
    else
        VERSION="patched"
    fi
fi

if [[ "$WORK" != /* ]]; then
    WORK="$PWD/$WORK"
fi
mkdir -p "$WORK"
WORK="$(readlink -f -- "$WORK")"
APPDIR="$WORK/CitrixWorkspace.AppDir"
OUT="${OUT:-$ROOT/dist/Citrix_Workspace_${VERSION}-x86_64.AppImage}"
if [[ "$OUT" != /* ]]; then
    OUT="$PWD/$OUT"
fi
mkdir -p "$(dirname "$OUT")"
OUT="$(readlink -f -- "$OUT")"

need python3
need tar
mkdir -p "$WORK"

say "Preparing work directory: $WORK"
rm -rf "$APPDIR"

prepare_appdir_from_package "$CLIENT_PACKAGE" "$APPDIR" "$WORK"
ICAROOT="$APPDIR/opt/Citrix/ICAClient"

if [[ -n "$USB_PACKAGE" ]]; then
    if ! merge_usb_package \
        "$USB_PACKAGE" \
        "$ICAROOT" \
        "$APPDIR/etc/udev/rules.d" \
        "$WORK"; then
        if [[ "$AUTO_USB" == "1" ]]; then
            warn "continuing without USB support"
        else
            die "failed to merge USB support from $USB_PACKAGE"
        fi
    fi
fi

ensure_webkit "$ICAROOT" "$APPDIR" "$WORK"
ICAROOT="$APPDIR/opt/Citrix/ICAClient"

if [[ "$FETCH_LIBS" == "1" ]]; then
    say "Bundling additional Ubuntu 22.04 runtime libraries"
    python3 "$HERE/fetch_jammy_libs.py" "$APPDIR" "$WORK/jammy"
else
    warn "skipping Ubuntu runtime library fetch"
fi

say "Patching WebKit helper paths for AppImage relocation"
patch_webkit_libraries "$APPDIR/usr/lib/x86_64-linux-gnu"

say "Rewriting absolute configuration symlinks"
python3 "$HERE/relativize_symlinks.py" "$APPDIR"

say "Preparing Citrix configuration"
prepare_config "$ICAROOT" fresh

chmod 0755 "$ICAROOT/ctxusb" "$ICAROOT/ctxusbd" "$ICAROOT/ctx_usb_isactive" 2>/dev/null || true

say "Installing launcher and desktop integration files"
install_fresh_launcher "$APPDIR" "$ICAROOT"

say "Verifying patch and required libraries"
validate_fresh_appdir "$APPDIR" "$ICAROOT"

APPIMAGETOOL="$(prepare_appimagetool)"

say "Building AppImage: $OUT"
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
ARCH=x86_64 "$APPIMAGETOOL" --no-appstream --comp zstd "$APPDIR" "$OUT"

say "Done"
ls -lh "$OUT"
printf 'AppDir kept at %s (remove it to reclaim space)\n' "$APPDIR"
