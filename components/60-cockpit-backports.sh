#!/usr/bin/env bash
set -euo pipefail

# NAME: Install Cockpit (Backports)
# DESC: Install/update Cockpit from Ubuntu backports

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (or with sudo)." >&2
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "This component supports apt-based systems only." >&2
  exit 1
fi

if [[ ! -r /etc/os-release ]]; then
  echo "Cannot read /etc/os-release." >&2
  exit 1
fi

# shellcheck disable=SC1091
. /etc/os-release

if [[ -z "${VERSION_CODENAME:-}" ]]; then
  echo "VERSION_CODENAME is not set in /etc/os-release." >&2
  exit 1
fi

target_release="${VERSION_CODENAME}-backports"

echo "Installing Cockpit from: ${target_release}"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get -y install -t "${target_release}" cockpit

echo "Cockpit install/update complete from ${target_release}."
echo "Access at: https://<server-ip>:9090"
