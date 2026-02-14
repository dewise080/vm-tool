#!/usr/bin/env bash
set -euo pipefail

# NAME: Install Webmin
# DESC: Configure Webmin repo via setup script and install Webmin

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (or with sudo)." >&2
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "This component is intended for Debian/Ubuntu (apt-based) systems." >&2
  exit 1
fi

tmp_script="$(mktemp)"
trap 'rm -f "$tmp_script"' EXIT

curl -fsSL -o "$tmp_script" https://raw.githubusercontent.com/webmin/webmin/master/webmin-setup-repo.sh
sh "$tmp_script"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get -y install --install-recommends webmin

echo "Webmin installation complete."
echo "Access at: https://<server-ip>:10000"
