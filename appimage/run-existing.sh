#!/usr/bin/env bash
set -euo pipefail

SELF="$(readlink -f -- "${BASH_SOURCE[0]}")"
ICAROOT="${CITRIX_ICAROOT:-$(cd -- "$(dirname -- "$SELF")" && pwd)}"
PWD_BEFORE="$PWD"

resolve_path() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s/%s\n' "$PWD_BEFORE" "$1" ;;
    esac
}

LIBDIR="$ICAROOT/usr/lib/x86_64-linux-gnu"

export ICAROOT
export CITRIX_ICAROOT="$ICAROOT"
export CITRIX_USB_ICAROOT="$ICAROOT"
export GDK_BACKEND="${CITRIX_GDK_BACKEND:-x11}"
export WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1
export LD_LIBRARY_PATH="$LIBDIR:$ICAROOT/lib:$ICAROOT${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH="$ICAROOT:$ICAROOT/util:$PATH"

if [[ -d "$LIBDIR/webkit2gtk-4.0" ]]; then
    export WEBKIT_EXEC_PATH="$LIBDIR/webkit2gtk-4.0"
    export WEBKIT_INJECTED_BUNDLE_PATH="$LIBDIR/webkit2gtk-4.0/injected-bundle"
fi

mode="selfservice"
args=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --selfservice|--receiver|--configmgr|--conncenter|--wfica|--new-store)
            mode="${1#--}"
            shift
            break
            ;;
        --install-usb)
            exec "$ICAROOT/install-usb.sh" "${@:2}"
            ;;
        --diagnose)
            exec "$ICAROOT/diagnose.sh"
            ;;
        --help|-h)
            cat <<EOF
Citrix Workspace (existing installation: $ICAROOT)

Usage:
  $0 [--selfservice|--receiver|--configmgr|--conncenter|--wfica|--new-store] [args...]
  $0 --install-usb
  $0 --diagnose

The client is forced onto the X11 GDK backend so it runs through XWayland on
Wayland desktops. Set CITRIX_GDK_BACKEND=wayland to override for experiments.
EOF
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            break
            ;;
    esac
done

for arg in "$@"; do
    case "$mode" in
        wfica|new-store)
            if [[ -f "$arg" ]]; then
                args+=("$(resolve_path "$arg")")
            else
                args+=("$arg")
            fi
            ;;
        *)
            args+=("$arg")
            ;;
    esac
done

cd "$ICAROOT"

case "$mode" in
    selfservice)
        exec "$ICAROOT/selfservice" --icaroot "$ICAROOT" "${args[@]}"
        ;;
    wfica)
        exec "$ICAROOT/wfica" -icaroot "$ICAROOT" "${args[@]}"
        ;;
    configmgr)
        exec "$ICAROOT/util/configmgr" -icaroot "$ICAROOT" "${args[@]}"
        ;;
    conncenter)
        exec "$ICAROOT/util/conncenter" -icaroot "$ICAROOT" "${args[@]}"
        ;;
    receiver)
        exec "$ICAROOT/util/ctxwebhelper" "${args[@]}"
        ;;
    new-store)
        exec "$ICAROOT/util/new_store" -icaroot "$ICAROOT" "${args[@]}"
        ;;
    *)
        printf 'Unknown mode: %s\n' "$mode" >&2
        exit 2
        ;;
esac
