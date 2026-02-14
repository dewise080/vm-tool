#!/usr/bin/env bash
set -euo pipefail

# NAME: Install scrcpy v3.3.4
# DESC: Install scrcpy from GitHub release v3.3.4

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (or with sudo)." >&2
  exit 1
fi

ARCH="$(uname -m)"
VERSION="v3.3.4"

case "$ARCH" in
  x86_64)
    ASSET="scrcpy-linux-x86_64-${VERSION}.tar.gz"
    ;;
  *)
    echo "Unsupported architecture for this release asset: ${ARCH}" >&2
    echo "Supported by this component: x86_64" >&2
    exit 1
    ;;
esac

URL="https://github.com/Genymobile/scrcpy/releases/download/${VERSION}/${ASSET}"
INSTALL_DIR="/opt/scrcpy-${VERSION}"
BIN_LINK="/usr/local/bin/scrcpy"

if command -v apt-get >/dev/null 2>&1; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get -y install ca-certificates curl tar adb
elif command -v dnf >/dev/null 2>&1; then
  dnf -y install ca-certificates curl tar android-tools
elif command -v yum >/dev/null 2>&1; then
  yum -y install ca-certificates curl tar android-tools
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

archive="$tmpdir/$ASSET"
curl -fL "$URL" -o "$archive"

rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

tar -xzf "$archive" -C "$INSTALL_DIR" --strip-components=1

if [[ ! -x "$INSTALL_DIR/scrcpy" ]]; then
  echo "scrcpy binary not found after extraction." >&2
  exit 1
fi

ln -sf "$INSTALL_DIR/scrcpy" "$BIN_LINK"

if [[ -f "$INSTALL_DIR/scrcpy-server" ]]; then
  mkdir -p /usr/local/share/scrcpy
  install -m 0644 "$INSTALL_DIR/scrcpy-server" /usr/local/share/scrcpy/scrcpy-server
fi

echo "scrcpy ${VERSION} installed to ${INSTALL_DIR}"
echo "Binary: ${BIN_LINK}"
if command -v scrcpy >/dev/null 2>&1; then
  echo "Installed version: $(scrcpy --version | head -n 1)"
fi
