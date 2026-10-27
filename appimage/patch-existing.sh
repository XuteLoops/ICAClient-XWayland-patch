#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$HERE/common.sh"

usage() {
    cat <<EOF
Usage:
  $(basename "$0") --icaroot <path> [options]

Patch an existing Citrix Workspace installation in place.

Options:
  --icaroot PATH     Directory containing selfservice and wfica
  --usb PATH         Optional Citrix USB package to merge
  --install-usb      Install the USB daemon and udev rules after patching
  --work DIR         Work directory
  --no-backup        Do not save originals under .citrix-wayland-backup
  --help             Show this help

When the installer is run as a normal user, --install-usb re-runs this
operation through sudo.
EOF
}

ICAROOT=""
USB_PACKAGE=""
DO_INSTALL_USB=0
DO_BACKUP=1
WORK="${WORK:-$DEFAULT_WORK}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --icaroot|--existing)
            [[ $# -ge 2 ]] || die "$1 requires a path"
            ICAROOT="$2"
            shift 2
            ;;
        --usb)
            [[ $# -ge 2 ]] || die "--usb requires a path"
            USB_PACKAGE="$2"
            shift 2
            ;;
        --install-usb)
            DO_INSTALL_USB=1
            shift
            ;;
        --work)
            [[ $# -ge 2 ]] || die "--work requires a path"
            WORK="$2"
            shift 2
            ;;
        --no-backup)
            DO_BACKUP=0
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

[[ -n "$ICAROOT" ]] || { usage; die "--icaroot is required"; }
ICAROOT="$(abs_path "$ICAROOT")"
is_client_root "$ICAROOT" || die "not a Citrix Workspace installation: $ICAROOT"
[[ -n "$USB_PACKAGE" ]] && USB_PACKAGE="$(abs_path "$USB_PACKAGE")"
[[ -z "$USB_PACKAGE" || -f "$USB_PACKAGE" ]] || die "USB package not found: $USB_PACKAGE"

if [[ "$WORK" != /* ]]; then
    WORK="$PWD/$WORK"
fi
mkdir -p "$WORK"
WORK="$(readlink -f -- "$WORK")"
BACKUP="$ICAROOT/.citrix-wayland-backup"
if [[ "$DO_BACKUP" == "1" ]]; then
    mkdir -p "$BACKUP"
    if [[ ! -f "$BACKUP/config/.complete" && -d "$ICAROOT/config" ]]; then
        cp -a "$ICAROOT/config" "$BACKUP/config"
        : >"$BACKUP/config/.complete"
    fi
    if [[ -f "$ICAROOT/eula.txt" && ! -f "$BACKUP/eula.txt" ]]; then
        cp -a "$ICAROOT/eula.txt" "$BACKUP/eula.txt"
    fi
fi

if [[ -n "$USB_PACKAGE" ]]; then
    merge_usb_package "$USB_PACKAGE" "$ICAROOT" "$ICAROOT/etc/udev/rules.d" "$WORK" ||
        die "failed to merge USB support from $USB_PACKAGE"
fi

ensure_webkit "$ICAROOT" "$ICAROOT" "$WORK"

WEBKIT_BACKUP=""
if [[ "$DO_BACKUP" == "1" ]]; then
    WEBKIT_BACKUP="$BACKUP/webkit-libdir"
fi

say "Patching WebKit helper paths for the existing installation"
patch_webkit_libraries "$ICAROOT/usr/lib/x86_64-linux-gnu" "$WEBKIT_BACKUP"

say "Preparing Citrix configuration"
prepare_config "$ICAROOT" existing

chmod 0755 "$ICAROOT/ctxusb" "$ICAROOT/ctxusbd" "$ICAROOT/ctx_usb_isactive" 2>/dev/null || true

say "Installing the existing-install launcher"
install_existing_launcher "$ICAROOT"

if [[ "$DO_INSTALL_USB" == "1" ]]; then
    say "Installing USB redirection"
    if [[ $EUID -eq 0 ]]; then
        env CITRIX_USB_ICAROOT="$ICAROOT" APPDIR="$ICAROOT" "$ICAROOT/install-usb.sh"
    else
        exec sudo env CITRIX_USB_ICAROOT="$ICAROOT" APPDIR="$ICAROOT" "$ICAROOT/install-usb.sh"
    fi
fi

say "Done"
printf 'Launch with: %s/citrix-workspace\n' "$ICAROOT"
if [[ "$DO_BACKUP" == "1" ]]; then
    printf 'Original files are in %s\n' "$BACKUP"
fi
