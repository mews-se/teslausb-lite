#!/bin/bash
# installs teslausb-lite on Raspberry Pi OS Lite (trixie); --ble also builds
# tesla-control for keeping the car awake
set -euo pipefail

cd "$(dirname "$0")"
[ "$(id -u)" = 0 ] || { echo "run as root: sudo $0 $*" >&2; exit 1; }

# shellcheck source=/dev/null
. /etc/os-release
if [ "${VERSION_CODENAME:-}" != trixie ]; then
  echo "warning: made for Debian 13 (trixie), this is ${PRETTY_NAME:-unknown}" >&2
fi

install_rclone() {
  local arch version deb tmp
  case $(uname -m) in
    aarch64) arch=arm64 ;;
    armv7l) arch=arm-v7 ;;
    armv6l) arch=arm-v6 ;;
    x86_64) arch=amd64 ;;
    *) echo "no rclone package for $(uname -m)" >&2; exit 1 ;;
  esac
  version=$(curl -fsS https://downloads.rclone.org/version.txt | awk '{ print $2 }')
  if command -v rclone > /dev/null && [ "$(rclone version | awk 'NR == 1 { print $2 }')" = "$version" ]; then
    return
  fi
  deb=rclone-$version-linux-$arch.deb
  tmp=$(mktemp -d)
  curl -fsS -o "$tmp/$deb" "https://downloads.rclone.org/$version/$deb"
  curl -fsS -o "$tmp/SHA256SUMS" "https://downloads.rclone.org/$version/SHA256SUMS"
  (cd "$tmp" && grep " $deb\$" SHA256SUMS | sha256sum -c --quiet -)
  apt install -y "$tmp/$deb"
  rm -rf "$tmp"
}

install_tesla_control() {
  local tmp had_go=yes
  dpkg -s golang-go > /dev/null 2>&1 || had_go=no
  apt install -y golang-go bluez
  apt install -y pi-bluetooth 2> /dev/null || true
  tmp=$(mktemp -d)
  GOPATH=$tmp/go GOCACHE=$tmp/cache GOBIN=/usr/local/bin GOTOOLCHAIN=local \
    go install github.com/teslamotors/vehicle-command/cmd/tesla-control@v0.4.1
  rm -rf "$tmp"
  if [ "$had_go" = no ]; then
    apt purge -y golang-go
    apt autoremove -y
  fi
}

apt update
apt install -y exfatprogs dmsetup iw curl openssl
install_rclone
if [ "${1:-}" = --ble ]; then
  install_tesla_control
fi

install -m 755 teslausb-lite /usr/local/sbin/teslausb-lite
install -m 644 teslausb-lite.service /etc/systemd/system/teslausb-lite.service
if [ ! -e /etc/teslausb-lite.conf ]; then
  install -m 600 teslausb-lite.conf /etc/teslausb-lite.conf
fi

# the card loses power without warning, so keep the journal in memory
mkdir -p /etc/systemd/journald.conf.d
printf '[Journal]\nStorage=volatile\nRuntimeMaxUse=16M\n' > /etc/systemd/journald.conf.d/teslausb-lite.conf

reboot=no
config=/boot/firmware/config.txt
if [ -e "$config" ] && ! grep -q '^dtoverlay=dwc2' "$config"; then
  printf '\n[all]\ndtoverlay=dwc2\n' >> "$config"
  reboot=yes
fi

systemctl daemon-reload
systemctl enable teslausb-lite.service

echo
echo "installed. next:"
echo "  1. edit /etc/teslausb-lite.conf"
echo "  2. put an rclone config with your remote in /root/.config/rclone/rclone.conf"
if [ "$reboot" = yes ]; then
  echo "  3. reboot (USB gadget mode was just enabled)"
else
  echo "  3. systemctl restart teslausb-lite"
fi
