#!/usr/bin/env bash
set -euo pipefail

APPDIR=/app/citrix-workspace
export CITRIX_APPIMAGE_NO_INTEGRATE=1
export CITRIX_USB_ICAROOT="$APPDIR/opt/Citrix/ICAClient"

if [[ $# -eq 0 ]]; then
    exec "$APPDIR/AppRun" --selfservice
fi

case "$1" in
    --install-usb)
        printf 'USB redirection is not available inside the Flatpak sandbox.\n' >&2
        printf 'Use the native package or the AppImage for --install-usb.\n' >&2
        exit 2
        ;;
    --*)
        exec "$APPDIR/AppRun" "$@"
        ;;
esac

arg="$1"
shift

case "$arg" in
    file://*)
        path="${arg#file://}"
        if command -v python3 >/dev/null 2>&1; then
            path="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote(sys.argv[1]))' "$path")"
        else
            path="$(printf '%s' "$path" | sed -e 's/%20/ /g' -e 's/%23/#/g')"
        fi
        case "$path" in
            *.ica|*.ICA)
                exec "$APPDIR/AppRun" --wfica "$path" "$@"
                ;;
            *.cr|*.CR)
                exec "$APPDIR/AppRun" --new-store "$path" "$@"
                ;;
            *)
                exec "$APPDIR/AppRun" --selfservice "$path" "$@"
                ;;
        esac
        ;;
    *.ica|*.ICA)
        exec "$APPDIR/AppRun" --wfica "$arg" "$@"
        ;;
    *.cr|*.CR)
        exec "$APPDIR/AppRun" --new-store "$arg" "$@"
        ;;
    citrixapp:*)
        exec "$APPDIR/AppRun" --selfservice "$arg" "$@"
        ;;
    receiver:*|citrixweb:*|ctxaadsso:*|citrixauthwebviewdone:*|ctxlinuxamloauth:*)
        exec "$APPDIR/AppRun" --receiver "$arg" "$@"
        ;;
    *)
        exec "$APPDIR/AppRun" --selfservice "$arg" "$@"
        ;;
esac
