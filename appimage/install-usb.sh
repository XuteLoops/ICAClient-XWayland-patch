#!/usr/bin/env bash
set -euo pipefail

SELF="$(readlink -f -- "${BASH_SOURCE[0]}")"

if [[ -n "${APPDIR:-}" ]]; then
    APPDIR="$(cd -- "$APPDIR" && pwd)"
else
    APPDIR="$(cd -- "$(dirname -- "$SELF")" && pwd)"
fi

SRC="${CITRIX_USB_SRC:-$APPDIR/opt/Citrix/ICAClient}"
DST="${CITRIX_USB_ICAROOT:-/opt/Citrix/ICAClient}"

if [[ ! -x "$SRC/ctxusbd" && -x "$APPDIR/ctxusbd" ]]; then
    SRC="$APPDIR"
fi

if [[ ! -x "$SRC/ctxusbd" ]]; then
    echo "ctxusbd not found in $SRC" >&2
    exit 1
fi
if [[ ! -f "$APPDIR/etc/udev/rules.d/85-ica-usb.rules" ]]; then
    echo "85-ica-usb.rules not found in $APPDIR" >&2
    exit 1
fi
if [[ ! -e "$SRC/ctxusb" ]]; then
    echo "ctxusb not found in $SRC" >&2
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    exec sudo env APPDIR="$APPDIR" CITRIX_USB_ICAROOT="$DST" "$SELF" "$@"
fi

if [[ "$SRC" != "$DST" ]]; then
    install -d -m 0755 "$DST" "$DST/config"
    install -m 4755 "$SRC/ctxusb" "$DST/ctxusb"
    install -m 0755 "$SRC/ctxusbd" "$DST/ctxusbd"
    install -m 0755 "$SRC/ctx_usb_isactive" "$DST/ctx_usb_isactive"
    install -m 0644 "$SRC/config/module.ini" "$DST/config/module.ini"

    for f in usb.conf VDGUSB.DLL; do
        if [[ -f "$SRC/$f" ]]; then
            install -m 0644 "$SRC/$f" "$DST/$f"
        fi
    done

    shopt -s nullglob
    for f in "$SRC"/libctxusb*.so*; do
        install -m 0755 "$f" "$DST/$(basename "$f")"
    done
    shopt -u nullglob
fi

chmod 4755 "$DST/ctxusb"
chmod 0755 "$DST/ctxusbd" "$DST/ctx_usb_isactive"

cat > /etc/systemd/system/ctxusbd.service <<EOF
[Unit]
Description=Citrix USB daemon
After=network.target

[Service]
Type=forking
Environment=ICAROOT=$DST
RuntimeDirectory=ctxusbd
RuntimeDirectoryMode=0700
ExecStart=$DST/ctxusbd
Restart=on-failure
RestartSec=2
KillMode=control-group

[Install]
WantedBy=multi-user.target
EOF

install -m 0644 "$APPDIR/etc/udev/rules.d/85-ica-usb.rules" /etc/udev/rules.d/85-ica-usb.rules
while IFS= read -r rule; do
    [[ -n "$rule" ]] || continue
    install -m 0644 "$rule" "/etc/udev/rules.d/$(basename "$rule")"
done < <(find "$APPDIR" -type f \( -name '50-ica-mtch.rules' -o -name '69-ica-hid.rules' \) -print 2>/dev/null)

if command -v restorecon >/dev/null 2>&1; then
    restorecon -R "$DST" >/dev/null 2>&1 || true
fi

if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload
    systemctl enable ctxusbd.service
    systemctl restart ctxusbd.service || systemctl start ctxusbd.service
fi

if command -v udevadm >/dev/null 2>&1; then
    udevadm control --reload-rules || true
    udevadm trigger || true
fi

printf 'Citrix USB support installed in %s\n' "$DST"
printf 'Reconnect USB devices or log out and back in.\n'
