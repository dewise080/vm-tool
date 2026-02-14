#!/usr/bin/env bash
set -euo pipefail

# NAME: Zsh + Oh My Zsh
# DESC: Install zsh, set it as default shell, and install Oh My Zsh

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (or with sudo)." >&2
  exit 1
fi

install_pkgs() {
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get -y install zsh curl git ca-certificates
  elif command -v dnf >/dev/null 2>&1; then
    dnf -y install zsh curl git ca-certificates
  elif command -v yum >/dev/null 2>&1; then
    yum -y install zsh curl git ca-certificates
  else
    echo "No supported package manager found (apt/dnf/yum)." >&2
    exit 1
  fi
}

pick_user() {
  local detected=""

  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    detected="$SUDO_USER"
  fi

  read -r -p "Target username for zsh/Oh My Zsh [${detected:-none}]: " input_user
  TARGET_USER="${input_user:-$detected}"

  if [[ -z "$TARGET_USER" ]]; then
    echo "Target username is required." >&2
    exit 1
  fi

  if ! id "$TARGET_USER" >/dev/null 2>&1; then
    echo "User '$TARGET_USER' does not exist." >&2
    exit 1
  fi
}

set_default_shell() {
  local zsh_path
  zsh_path="$(command -v zsh)"

  if [[ -z "$zsh_path" ]]; then
    echo "zsh binary not found after install." >&2
    exit 1
  fi

  # Ensure zsh is in valid login shells list on distros that use /etc/shells.
  if [[ -f /etc/shells ]] && ! grep -qx "$zsh_path" /etc/shells; then
    echo "$zsh_path" >> /etc/shells
  fi

  chsh -s "$zsh_path" "$TARGET_USER"
}

install_oh_my_zsh() {
  local user_home
  user_home="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

  if [[ -z "$user_home" || ! -d "$user_home" ]]; then
    echo "Could not determine home directory for '$TARGET_USER'." >&2
    exit 1
  fi

  if [[ -d "$user_home/.oh-my-zsh" ]]; then
    echo "Oh My Zsh already installed for '$TARGET_USER'. Skipping."
    return 0
  fi

  # Unattended install; CHSH is done by this script explicitly.
  su - "$TARGET_USER" -c 'RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'
}

install_pkgs
pick_user
set_default_shell
install_oh_my_zsh

echo "Completed: zsh + Oh My Zsh configured for '$TARGET_USER'."
echo "The shell change applies on next login for that user."
