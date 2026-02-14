#!/usr/bin/env bash
set -euo pipefail

# NAME: Create Admin User
# DESC: Create a sudo-capable admin user interactively

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (or with sudo)." >&2
  exit 1
fi

read -r -p "New username: " username
if [[ -z "$username" ]]; then
  echo "Username cannot be empty." >&2
  exit 1
fi

if id "$username" >/dev/null 2>&1; then
  echo "User '$username' already exists."
else
  useradd -m -s /bin/bash "$username"
  echo "Set password for '$username':"
  passwd "$username"
fi

if getent group sudo >/dev/null 2>&1; then
  usermod -aG sudo "$username"
elif getent group wheel >/dev/null 2>&1; then
  usermod -aG wheel "$username"
else
  echo "Neither 'sudo' nor 'wheel' group exists; skipping admin group assignment." >&2
fi

echo "User setup complete for '$username'."
