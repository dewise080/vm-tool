#!/usr/bin/env bash
set -euo pipefail

# NAME: Install Xpra Beta (Server+Client)
# DESC: Add xpra.org beta repo and install latest Xpra server/client packages

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (or with sudo)." >&2
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "This component is intended for Debian/Ubuntu (apt-based) systems." >&2
  exit 1
fi

if [[ ! -r /etc/os-release ]]; then
  echo "Cannot read /etc/os-release." >&2
  exit 1
fi

# shellcheck disable=SC1091
. /etc/os-release

DISTRO_CODENAME="${VERSION_CODENAME:-}"
if [[ -z "$DISTRO_CODENAME" ]]; then
  echo "VERSION_CODENAME is not set in /etc/os-release." >&2
  exit 1
fi

REPO_BASENAME="xpra-beta"
REPO_URL="https://raw.githubusercontent.com/Xpra-org/xpra/master/packaging/repos/${DISTRO_CODENAME}/${REPO_BASENAME}.sources"
REPO_FILE="/etc/apt/sources.list.d/${REPO_BASENAME}.sources"
KEY_FILE="/usr/share/keyrings/xpra.asc"

echo "Preparing Xpra beta repository for codename: ${DISTRO_CODENAME}"

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get -y install ca-certificates wget apt-transport-https software-properties-common

wget -q -O "$KEY_FILE" https://xpra.org/xpra.asc

if ! wget -q --spider "$REPO_URL"; then
  echo "No xpra beta repo file found for codename '${DISTRO_CODENAME}'." >&2
  echo "Expected: $REPO_URL" >&2
  exit 1
fi

wget -q -O "$REPO_FILE" "$REPO_URL"

apt-get update

# 'xpra' is the primary package on Debian/Ubuntu and includes server/client tools.
DEBIAN_FRONTEND=noninteractive apt-get -y install xpra

# Install split packages when available on some distributions/releases.
if apt-cache show xpra-server >/dev/null 2>&1; then
  DEBIAN_FRONTEND=noninteractive apt-get -y install xpra-server
fi
if apt-cache show xpra-client >/dev/null 2>&1; then
  DEBIAN_FRONTEND=noninteractive apt-get -y install xpra-client
fi

echo "Xpra beta repository configured and packages installed."
if command -v xpra >/dev/null 2>&1; then
  echo "Installed version: $(xpra --version | head -n 1)"
fi
