#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=appimage/common.sh
source "$HERE/appimage/common.sh"

usage() {
    cat <<EOF
Usage:
  $(basename "$0") build --package <client-package> [--usb <usb-package>] [options]
  $(basename "$0") existing --icaroot <path> [--usb <usb-package>] [options]

Modes:
  build       Extract an official Citrix package and build a portable AppImage.
  existing    Patch an existing Citrix Workspace installation in place.

The repository does not contain Citrix software. Supply an official package
from Citrix, or use existing with an installation already on the system.

Examples:
  $(basename "$0") build --package ~/Downloads/icaclient-gcc-8_26.04.10.1_amd64.deb
  $(basename "$0") build --package ~/Downloads/icaclient-*.rpm --usb ~/Downloads/ctxusb-*.rpm
  sudo $(basename "$0") existing --icaroot /opt/Citrix/ICAClient --install-usb

Run with --help after a mode for mode-specific options.
EOF
}

[[ $# -gt 0 ]] || { usage; exit 2; }

mode="$1"
shift

case "$mode" in
    build|existing)
        ;;
    --help|-h|help)
        usage
        exit 0
        ;;
    *)
        die "unknown mode: $mode"
        ;;
esac

usb=""
no_usb=0
declare -a filtered=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --usb)
            [[ $# -ge 2 ]] || die "--usb requires a path"
            usb="$2"
            filtered+=("$1" "$2")
            shift 2
            ;;
        --no-usb)
            no_usb=1
            filtered+=("$1")
            shift
            ;;
        *)
            filtered+=("$1")
            shift
            ;;
    esac
done

if [[ "$no_usb" == "0" && -z "$usb" ]]; then
    for candidate in \
        "$PWD"/ctxusb*.deb \
        "$PWD"/ctxusb*.rpm \
        "$PWD"/ctxusb*.tar \
        "$PWD"/ctxusb*.tar.gz \
        "$PWD"/ctxusb*.tgz \
        "$PWD"/ctxusb*.tar.xz \
        "$PWD"/ctxusb*.txz \
        "$PWD"/ctxusb*.tar.bz2 \
        "$PWD"/ctxusb*.tbz2 \
        "$PWD"/ctxusb*.tar.zst \
        "$PWD"/ctxusb*.tzst; do
        if [[ -f "$candidate" ]]; then
            usb="$candidate"
            filtered+=(--usb "$candidate")
            break
        fi
    done
fi

if [[ -n "$usb" ]]; then
    say "Using USB package: $usb"
fi

case "$mode" in
    build)
        exec bash "$HERE/appimage/build-appimage.sh" "${filtered[@]}"
        ;;
    existing)
        exec bash "$HERE/appimage/patch-existing.sh" "${filtered[@]}"
        ;;
esac
