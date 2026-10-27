#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${APPDIR:-}" ]]; then
    APPDIR="$(cd -- "$APPDIR" && pwd)"
else
    APPDIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
fi

ICAROOT="$APPDIR/opt/Citrix/ICAClient"
TARGET="${APPIMAGE:-$APPDIR/AppRun}"
TARGET="$(readlink -f -- "$TARGET")"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
APPS="$DATA/applications"
ICON="$DATA/icons/citrix-workspace.png"
STATE="${XDG_CONFIG_HOME:-$HOME/.config}/citrix-workspace-appimage"

mkdir -p "$APPS" "$(dirname "$ICON")" "$STATE"
install -m 0644 "$APPDIR/citrix-workspace.png" "$ICON"

cat > "$APPS/citrix-workspace.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Citrix Workspace
Comment=Access virtual apps and desktops
Exec="$TARGET" --selfservice
Icon=$ICON
Terminal=false
Categories=Network;
StartupNotify=true
EOF

cat > "$APPS/citrix-wfica.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Citrix Workspace Engine
Exec="$TARGET" --wfica %f
Icon=$ICON
Terminal=false
NoDisplay=true
MimeType=application/x-ica;
Categories=Network;
StartupWMClass=Wfica
EOF

cat > "$APPS/citrix-configmgr.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Citrix Workspace Configuration Manager
Exec="$TARGET" --configmgr
Icon=$ICON
Terminal=false
NoDisplay=true
Categories=Network;
EOF

cat > "$APPS/citrix-conncenter.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Citrix Workspace Connection Center
Exec="$TARGET" --conncenter
Icon=$ICON
Terminal=false
NoDisplay=true
Categories=Network;
EOF

cat > "$APPS/citrix-app.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Citrix Workspace Application Launcher
Exec="$TARGET" --selfservice %u
Icon=$ICON
Terminal=false
NoDisplay=true
MimeType=x-scheme-handler/citrixapp;
Categories=Network;
EOF

cat > "$APPS/citrix-receiver.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Citrix Workspace Receiver
Exec="$TARGET" --receiver %u
Icon=$ICON
Terminal=false
NoDisplay=true
MimeType=x-scheme-handler/receiver;
Categories=Network;
EOF

cat > "$APPS/citrix-webhelper.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Citrix Workspace Web Helper
Exec="$TARGET" --receiver %u
Icon=$ICON
Terminal=false
NoDisplay=true
MimeType=x-scheme-handler/citrixweb;x-scheme-handler/ctxaadsso;x-scheme-handler/citrixauthwebviewdone;x-scheme-handler/ctxlinuxamloauth;
Categories=Network;
EOF

cat > "$APPS/citrix-new-store.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Citrix Workspace Store Setup
Exec="$TARGET" --new-store %f
Icon=$ICON
Terminal=false
NoDisplay=true
MimeType=application/vnd.citrix.receiver.configure;
Categories=Network;
EOF

MIME_XML="$(find "$ICAROOT" -maxdepth 2 -iname '*mime*type*.xml' -print -quit 2>/dev/null || true)"
if [[ -n "$MIME_XML" ]]; then
    MIME_DIR="$DATA/mime"
    mkdir -p "$MIME_DIR/packages"
    install -m 0644 "$MIME_XML" "$MIME_DIR/packages/citrix-workspace.xml"
    if command -v update-mime-database >/dev/null 2>&1; then
        update-mime-database "$MIME_DIR" >/dev/null 2>&1 || true
    elif command -v xdg-mime >/dev/null 2>&1; then
        xdg-mime install "$MIME_XML" >/dev/null 2>&1 || true
    fi
fi

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$APPS" >/dev/null 2>&1 || true
fi

set_default() {
    local mime="$1"
    local desktop="$2"
    if command -v gio >/dev/null 2>&1; then
        gio mime "$mime" "$desktop" >/dev/null 2>&1 && return 0
    fi
    if command -v xdg-mime >/dev/null 2>&1; then
        xdg-mime default "$desktop" "$mime" >/dev/null 2>&1 || true
    fi
}

set_default application/x-ica citrix-wfica.desktop
set_default x-scheme-handler/citrixapp citrix-app.desktop
set_default x-scheme-handler/receiver citrix-receiver.desktop
set_default x-scheme-handler/citrixweb citrix-webhelper.desktop
set_default x-scheme-handler/ctxaadsso citrix-webhelper.desktop
set_default x-scheme-handler/citrixauthwebviewdone citrix-webhelper.desktop
set_default x-scheme-handler/ctxlinuxamloauth citrix-webhelper.desktop
set_default application/vnd.citrix.receiver.configure citrix-new-store.desktop

if command -v kbuildsycoca6 >/dev/null 2>&1; then
    kbuildsycoca6 >/dev/null 2>&1 || true
elif command -v kbuildsycoca5 >/dev/null 2>&1; then
    kbuildsycoca5 >/dev/null 2>&1 || true
fi

printf '%s\n' "$TARGET" > "$STATE/integrated-target"

printf 'Integrated Citrix Workspace for %s\n' "$(id -un)"
printf 'Launcher: %s/citrix-workspace.desktop\n' "$APPS"
printf 'Re-run this command after moving the AppImage to a new path.\n'
