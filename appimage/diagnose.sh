#!/usr/bin/env bash
set -u

if [[ -n "${APPDIR:-}" ]]; then
    APPDIR="$(cd -- "$APPDIR" && pwd)"
else
    APPDIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
fi

if [[ -n "${CITRIX_ICAROOT:-}" && -f "$CITRIX_ICAROOT/selfservice" ]]; then
    ICAROOT="$(cd -- "$CITRIX_ICAROOT" && pwd)"
elif [[ -f "$APPDIR/opt/Citrix/ICAClient/selfservice" ]]; then
    ICAROOT="$APPDIR/opt/Citrix/ICAClient"
elif [[ -f "$APPDIR/selfservice" ]]; then
    ICAROOT="$APPDIR"
else
    ICAROOT="$APPDIR/opt/Citrix/ICAClient"
fi

if [[ -d "$APPDIR/usr/lib/x86_64-linux-gnu" ]]; then
    LIBDIR="$APPDIR/usr/lib/x86_64-linux-gnu"
elif [[ -d "$ICAROOT/usr/lib/x86_64-linux-gnu" ]]; then
    LIBDIR="$ICAROOT/usr/lib/x86_64-linux-gnu"
else
    LIBDIR="$ICAROOT/lib"
fi

echo "Installation:     $ICAROOT"
echo "AppDir:            $APPDIR"
echo "Library dir:       $LIBDIR"
echo "DISPLAY:           ${DISPLAY:-<unset>}"
echo "WAYLAND_DISPLAY:   ${WAYLAND_DISPLAY:-<unset>}"
echo "XDG_SESSION_TYPE:  ${XDG_SESSION_TYPE:-<unset>}"
echo "GDK_BACKEND:       ${GDK_BACKEND:-<unset>}"
echo "CITRIX_GDK_BACKEND:${CITRIX_GDK_BACKEND:-<unset>}"

if [[ -S /tmp/.X11-unix/X0 ]]; then
    echo "XWayland socket:   /tmp/.X11-unix/X0 present"
else
    echo "XWayland socket:   /tmp/.X11-unix/X0 missing"
fi

echo
echo "== bundled runtime libraries =="
for lib in libjpeg.so.8 libsoup-2.4.so.1 libwebkit2gtk-4.0.so.37 libjavascriptcoregtk-4.0.so.18; do
    if [[ -e "$LIBDIR/$lib" ]]; then
        echo "  OK      $lib"
    else
        echo "  MISSING $lib"
    fi
done

echo
echo "== WebKit helpers =="
for helper in WebKitWebProcess WebKitNetworkProcess; do
    if [[ -x "$LIBDIR/webkit2gtk-4.0/$helper" ]]; then
        echo "  OK      $helper"
    else
        echo "  MISSING $helper"
    fi
done
if [[ -f "$LIBDIR/libwebkit2gtk-4.0.so.37" ]] &&
    grep -a -q 'usr//lib/x86_64-linux-gnu/webkit2gtk-4.0' "$LIBDIR/libwebkit2gtk-4.0.so.37"; then
    echo "  OK      WebKit relocation patch applied"
else
    echo "  MISSING WebKit relocation patch"
fi

echo
echo "== unresolved dynamic libraries =="
LD_LIBRARY_PATH="$LIBDIR:$ICAROOT/lib:$ICAROOT" ldd "$ICAROOT/selfservice" 2>/dev/null | grep 'not found' || echo "  selfservice: OK"
LD_LIBRARY_PATH="$LIBDIR:$ICAROOT/lib:$ICAROOT" ldd "$ICAROOT/wfica" 2>/dev/null | grep 'not found' || echo "  wfica: OK"

echo
echo "== installation state =="
if grep -q '^GenericUSB=on' "$ICAROOT/config/module.ini" 2>/dev/null; then
    echo "  module.ini GenericUSB: enabled"
else
    echo "  module.ini GenericUSB: not enabled"
fi
if [[ -f "$ICAROOT/eula.txt" && -f "$ICAROOT/config/eula.txt" ]]; then
    echo "  EULA license files:    present (root + config)"
elif [[ -f "$ICAROOT/config/eula.txt" ]]; then
    echo "  EULA license files:    incomplete (missing root eula.txt)"
elif [[ -f "$ICAROOT/eula.txt" ]]; then
    echo "  EULA license files:    incomplete (missing config/eula.txt)"
else
    echo "  EULA license files:    missing"
fi
INTEGRATION_MARKER="${XDG_CONFIG_HOME:-$HOME/.config}/citrix-workspace-appimage/integrated-target"
if [[ -f "$INTEGRATION_MARKER" ]]; then
    echo "  desktop integration:  $(<"$INTEGRATION_MARKER")"
elif [[ -x "$APPDIR/AppRun" ]]; then
    echo "  desktop integration:  not installed (auto on first GUI launch; use --integrate)"
else
    echo "  desktop integration:  not used for this installation"
fi
if [[ -x "$ICAROOT/ctxusbd" || -x /opt/Citrix/ICAClient/ctxusbd ]]; then
    echo "  USB helper:            installed"
else
    echo "  USB helper:            not installed (use --install-usb)"
fi
if command -v systemctl >/dev/null 2>&1; then
    systemctl is-active ctxusbd.service 2>/dev/null | sed 's/^/  ctxusbd.service:      /'
fi

echo
echo "Launch the client with:"
echo "  $0 --selfservice"
