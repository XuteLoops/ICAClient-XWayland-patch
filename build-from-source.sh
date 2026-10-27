#!/usr/bin/env bash
set -euo pipefail

cat >&2 <<'EOF'
ERROR: build-from-source.sh is retired.

The repository no longer ships or builds from a proprietary source tree.
Use an official Citrix package or an existing installation:

  ./patch-citrix.sh build --package /path/to/icaclient.deb
  sudo ./patch-citrix.sh existing --icaroot /opt/Citrix/ICAClient

See README.md for details.
EOF
exit 1
