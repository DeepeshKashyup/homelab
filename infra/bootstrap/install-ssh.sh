#!/usr/bin/env bash
# infra/bootstrap/install-ssh.sh
#
# Phase 1 of node bootstrap: install and enable OpenSSH server with sane
# defaults, open the firewall for it, and print the info needed to set a
# DHCP reservation on the router.
#
# Run with sudo on the target node:
#   sudo bash infra/bootstrap/install-ssh.sh
#
# Password auth is left ENABLED after this script — that's intentional, so
# you can copy a public key over from the jump box next. Run
# harden-ssh.sh afterwards to lock it down to key-only auth.

set -euo pipefail

echo "==> Updating package lists"
apt-get update -y

echo "==> Installing openssh-server and ufw"
apt-get install -y openssh-server ufw

echo "==> Enabling and starting ssh.service"
systemctl enable --now ssh

echo "==> Allowing SSH through ufw"
ufw allow OpenSSH
# Enable ufw non-interactively if it isn't already active.
if ! ufw status | grep -q "Status: active"; then
  ufw --force enable
fi

echo
echo "==> Node network info (for router DHCP reservation)"
echo "Hostname: $(hostname)"
ip -o -4 addr show scope global | awk '{print $2, $4}' | while read -r iface addr; do
  mac=$(ip link show "$iface" | awk '/link\/ether/ {print $2}')
  echo "  interface=$iface  ip=$addr  mac=$mac"
done

echo
echo "==> ssh.service status"
systemctl is-active ssh
systemctl is-enabled ssh

echo
echo "Done. Next: copy your jump box's public key over (ssh-copy-id), confirm"
echo "key-based login works, then run infra/bootstrap/harden-ssh.sh."
