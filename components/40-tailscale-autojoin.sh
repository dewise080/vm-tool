#!/usr/bin/env bash
set -euo pipefail

# NAME: Tailscale Auto-Join
# DESC: Install Tailscale and join tailnet using preset auth key

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (or with sudo)." >&2
  exit 1
fi

curl -fsSL https://tailscale.com/install.sh | sh
tailscale up --auth-key=tskey-auth-kaiSCrdRiS11CNTRL-DwQMpiTmV4Q69u3arVRc3QcS6doKj8AF

echo "Tailscale install and tailnet join completed."
