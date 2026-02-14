#!/usr/bin/env bash
set -euo pipefail

# NAME: Node/NPM + AI CLIs
# DESC: Detect/install Node.js + npm, then optionally install Codex and Gemini CLI

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (or with sudo)." >&2
  exit 1
fi

prompt_yes_no() {
  local prompt="$1"
  local reply
  read -r -p "$prompt [y/N]: " reply
  [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]
}

install_node_npm() {
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get -y install nodejs npm
  elif command -v dnf >/dev/null 2>&1; then
    dnf -y install nodejs npm
  elif command -v yum >/dev/null 2>&1; then
    yum -y install nodejs npm
  else
    echo "No supported package manager found (apt/dnf/yum)." >&2
    exit 1
  fi
}

if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
  echo "Node.js and npm already installed."
else
  echo "Node.js and/or npm not found. Installing..."
  install_node_npm
fi

if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
  echo "Node.js/npm installation did not complete successfully." >&2
  exit 1
fi

echo "node: $(node -v)"
echo "npm:  $(npm -v)"

if prompt_yes_no "Install @openai/codex globally now?"; then
  npm i -g @openai/codex
else
  echo "Skipped @openai/codex"
fi

if prompt_yes_no "Install @google/gemini-cli globally now?"; then
  npm install -g @google/gemini-cli
else
  echo "Skipped @google/gemini-cli"
fi

echo "Node/NPM and optional global CLI installation step complete."
