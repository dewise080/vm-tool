#!/usr/bin/env bash
set -euo pipefail

# NAME: Install OpenClaw
# DESC: Install OpenClaw using official installer script

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (or with sudo)." >&2
  exit 1
fi

if command -v apt-get >/dev/null 2>&1; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get -y install curl bash ca-certificates
elif command -v dnf >/dev/null 2>&1; then
  dnf -y install curl bash ca-certificates
elif command -v yum >/dev/null 2>&1; then
  yum -y install curl bash ca-certificates
fi

echo "Official OpenClaw installer options:"
echo "  1) Install + onboarding (recommended)"
echo "  2) Install only (--no-onboard)"
read -r -p "Selection [1-2]: " selection

case "$selection" in
  1)
    curl -fsSL https://openclaw.ai/install.sh | bash
    ;;
  2)
    curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard
    ;;
  *)
    echo "Invalid selection." >&2
    exit 1
    ;;
esac

if command -v openclaw >/dev/null 2>&1; then
  echo "OpenClaw installed: $(openclaw --version 2>/dev/null || echo 'version command unavailable')"
  echo "Optional checks: openclaw doctor && openclaw status"
else
  echo "OpenClaw installer finished, but 'openclaw' is not in current PATH yet."
  echo "Open a new shell, then run: openclaw doctor"
fi
