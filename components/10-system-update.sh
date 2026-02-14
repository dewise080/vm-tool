#!/usr/bin/env bash
set -euo pipefail

# NAME: System Update
# DESC: Update package index and upgrade installed packages

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (or with sudo)." >&2
  exit 1
fi

if command -v apt-get >/dev/null 2>&1; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
  echo "System update complete (apt)."
elif command -v dnf >/dev/null 2>&1; then
  dnf -y upgrade --refresh
  echo "System update complete (dnf)."
elif command -v yum >/dev/null 2>&1; then
  yum -y update
  echo "System update complete (yum)."
else
  echo "No supported package manager found (apt/dnf/yum)." >&2
  exit 1
fi
