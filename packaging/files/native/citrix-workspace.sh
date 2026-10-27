#!/bin/sh
set -eu

export CITRIX_APPIMAGE_NO_INTEGRATE="${CITRIX_APPIMAGE_NO_INTEGRATE:-1}"
export CITRIX_USB_ICAROOT="${CITRIX_USB_ICAROOT:-/opt/citrix-workspace/opt/Citrix/ICAClient}"

exec /opt/citrix-workspace/AppRun "$@"
