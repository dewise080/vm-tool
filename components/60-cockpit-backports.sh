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

has_backports() {
  apt-cache policy | grep -q "${target_release}"
}

enable_backports_if_missing() {
  if has_backports; then
    return 0
  fi

  if [[ "${ID:-}" != "ubuntu" ]]; then
    echo "Backports pocket '${target_release}' is not available in apt sources." >&2
    echo "Enable it manually, then re-run this component." >&2
    exit 1
  fi

  backports_list="/etc/apt/sources.list.d/99-${VERSION_CODENAME}-backports.list"
  echo "Backports not found; adding ${backports_list}"
  cat > "${backports_list}" <<EOF
deb http://archive.ubuntu.com/ubuntu ${target_release} main restricted universe multiverse
EOF
}

cockpit_installed() {
  dpkg-query -W -f='${Status}\n' cockpit 2>/dev/null | grep -q "install ok installed" || \
    dpkg-query -W -f='${Status}\n' cockpit-ws 2>/dev/null | grep -q "install ok installed"
}

enable_root_login() {
  local disallowed_file tmpfile
  disallowed_file="/etc/cockpit/disallowed-users"

  mkdir -p /etc/cockpit
  if [[ -f "$disallowed_file" ]]; then
    tmpfile="$(mktemp)"
    # Remove only exact "root" entries and preserve any other disallowed users.
    awk '$0 != "root"' "$disallowed_file" > "$tmpfile"
    install -m 0644 "$tmpfile" "$disallowed_file"
    rm -f "$tmpfile"
  fi

  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart cockpit.socket 2>/dev/null || true
    systemctl restart cockpit 2>/dev/null || true
  fi
}

if cockpit_installed; then
  echo "Cockpit already installed. Skipping installation."
else
  echo "Installing Cockpit from: ${target_release}"
  apt-get update
  enable_backports_if_missing
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get -y install -t "${target_release}" cockpit
fi

enable_root_login

echo "Cockpit root login enabled (root removed from /etc/cockpit/disallowed-users if present)."
echo "Access at: https://<server-ip>:9090"
