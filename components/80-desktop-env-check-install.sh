#!/usr/bin/env bash
set -euo pipefail

# NAME: Desktop Env Check/Install
# DESC: Check DE/X11/Wayland and optionally install lightweight desktop stack

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (or with sudo)." >&2
  exit 1
fi

has_x11_sessions() {
  compgen -G "/usr/share/xsessions/*.desktop" >/dev/null 2>&1
}

has_wayland_sessions() {
  compgen -G "/usr/share/wayland-sessions/*.desktop" >/dev/null 2>&1
}

has_desktop_environment() {
  has_x11_sessions || has_wayland_sessions
}

install_debian() {
  local choice="$1"

  case "$choice" in
    xfce)
      DEBIAN_FRONTEND=noninteractive apt-get -y install xfce4 xfce4-goodies lightdm xorg
      ;;
    lxqt)
      DEBIAN_FRONTEND=noninteractive apt-get -y install lxqt sddm xorg
      ;;
    lxde)
      DEBIAN_FRONTEND=noninteractive apt-get -y install lxde-core lightdm xorg
      ;;
    gnome)
      DEBIAN_FRONTEND=noninteractive apt-get -y install ubuntu-gnome-desktop gdm3
      ;;
    kde)
      DEBIAN_FRONTEND=noninteractive apt-get -y install kde-standard sddm
      ;;
    *)
      echo "Unsupported option: $choice" >&2
      exit 1
      ;;
  esac
}

install_fedora_rhel() {
  local choice="$1"

  case "$choice" in
    xfce)
      dnf -y groupinstall "Xfce" || dnf -y install @xfce-desktop-environment
      dnf -y install lightdm xorg-x11-server-Xorg
      ;;
    lxqt)
      dnf -y groupinstall "LXQt" || dnf -y install @lxqt-desktop-environment
      dnf -y install sddm xorg-x11-server-Xorg
      ;;
    lxde)
      dnf -y groupinstall "LXDE" || dnf -y install @lxde-desktop-environment
      dnf -y install lightdm xorg-x11-server-Xorg
      ;;
    gnome)
      dnf -y groupinstall "GNOME Desktop Environment" || dnf -y install @gnome-desktop
      dnf -y install gdm
      ;;
    kde)
      dnf -y groupinstall "KDE Plasma Workspaces" || dnf -y install @kde-desktop-environment
      dnf -y install sddm
      ;;
    *)
      echo "Unsupported option: $choice" >&2
      exit 1
      ;;
  esac
}

install_yum() {
  local choice="$1"

  case "$choice" in
    xfce)
      yum -y groupinstall "Xfce" || yum -y install @xfce-desktop-environment
      yum -y install lightdm xorg-x11-server-Xorg
      ;;
    lxqt)
      yum -y groupinstall "LXQt" || yum -y install @lxqt-desktop-environment
      yum -y install sddm xorg-x11-server-Xorg
      ;;
    lxde)
      yum -y groupinstall "LXDE" || yum -y install @lxde-desktop-environment
      yum -y install lightdm xorg-x11-server-Xorg
      ;;
    gnome)
      yum -y groupinstall "GNOME Desktop Environment" || yum -y install @gnome-desktop
      yum -y install gdm
      ;;
    kde)
      yum -y groupinstall "KDE Plasma Workspaces" || yum -y install @kde-desktop-environment
      yum -y install sddm
      ;;
    *)
      echo "Unsupported option: $choice" >&2
      exit 1
      ;;
  esac
}

enable_display_manager_if_present() {
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl list-unit-files | grep -q '^lightdm\.service'; then
      systemctl enable lightdm >/dev/null 2>&1 || true
    elif systemctl list-unit-files | grep -q '^gdm\.service'; then
      systemctl enable gdm >/dev/null 2>&1 || true
    elif systemctl list-unit-files | grep -q '^sddm\.service'; then
      systemctl enable sddm >/dev/null 2>&1 || true
    fi
    systemctl set-default graphical.target >/dev/null 2>&1 || true
  fi
}

print_status() {
  local de_state="missing"
  local x11_state="missing"
  local wayland_state="missing"

  if has_desktop_environment; then
    de_state="present"
  fi
  if has_x11_sessions; then
    x11_state="available"
  fi
  if has_wayland_sessions; then
    wayland_state="available"
  fi

  echo "Desktop environment: $de_state"
  echo "X11 sessions:        $x11_state"
  echo "Wayland sessions:    $wayland_state"
}

print_status

if has_desktop_environment && (has_x11_sessions || has_wayland_sessions); then
  echo "Desktop and session protocol support detected. No install required."
  exit 0
fi

echo
echo "No complete desktop/session setup detected."
echo "Choose lightweight desktop to install:"
echo "  1) xfce (recommended)"
echo "  2) lxqt"
echo "  3) lxde"
echo "  4) gnome (Wayland-capable)"
echo "  5) kde plasma (Wayland-capable)"
echo "  6) cancel"
read -r -p "Selection [1-6]: " selection

case "$selection" in
  1) choice="xfce" ;;
  2) choice="lxqt" ;;
  3) choice="lxde" ;;
  4) choice="gnome" ;;
  5) choice="kde" ;;
  6)
    echo "Cancelled."
    exit 0
    ;;
  *)
    echo "Invalid selection." >&2
    exit 1
    ;;
esac

if command -v apt-get >/dev/null 2>&1; then
  apt-get update
  install_debian "$choice"
elif command -v dnf >/dev/null 2>&1; then
  install_fedora_rhel "$choice"
elif command -v yum >/dev/null 2>&1; then
  install_yum "$choice"
else
  echo "No supported package manager found (apt/dnf/yum)." >&2
  exit 1
fi

enable_display_manager_if_present

echo "Installation finished. Current status:"
print_status
echo "Reboot is recommended before first graphical login."
