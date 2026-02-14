#!/usr/bin/env bash
set -euo pipefail

# NAME: Passwordless Sudo
# DESC: Configure NOPASSWD sudo access for a selected user

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (or with sudo)." >&2
  exit 1
fi

if ! command -v visudo >/dev/null 2>&1; then
  echo "visudo is required but not found." >&2
  exit 1
fi

detected_user=""
if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
  detected_user="$SUDO_USER"
fi

read -r -p "Target username for passwordless sudo [${detected_user:-none}]: " input_user
TARGET_USER="${input_user:-$detected_user}"

if [[ -z "$TARGET_USER" ]]; then
  echo "Target username is required." >&2
  exit 1
fi

if ! id "$TARGET_USER" >/dev/null 2>&1; then
  echo "User '$TARGET_USER' does not exist." >&2
  exit 1
fi

sudoers_dir="/etc/sudoers.d"
sudoers_file="$sudoers_dir/${TARGET_USER}-nopasswd"
rule="$TARGET_USER ALL=(ALL) NOPASSWD:ALL"

tmpfile="$(mktemp)"
trap 'rm -f "$tmpfile"' EXIT
printf '%s\n' "$rule" > "$tmpfile"

chmod 0440 "$tmpfile"
if ! visudo -cf "$tmpfile" >/dev/null; then
  echo "Validation failed; not applying sudoers change." >&2
  exit 1
fi

install -d -m 0750 "$sudoers_dir"
install -m 0440 "$tmpfile" "$sudoers_file"

# Validate full sudoers config including include dirs after write.
if ! visudo -c >/dev/null; then
  echo "Global sudoers validation failed after update." >&2
  exit 1
fi

echo "Passwordless sudo enabled for '$TARGET_USER'."
echo "Rule written to: $sudoers_file"
