#!/usr/bin/env bash
# infra/bootstrap/enable-wol.sh
#
# Enables Wake-on-LAN (magic packet) on a node's wired NIC, and makes it
# persist across reboots -- ethtool's `wol g` setting alone resets every
# time the interface comes up unless something re-applies it.
#
# Prerequisite this script CANNOT do for you: Wake-on-LAN must also be
# enabled in the machine's BIOS/UEFI (look for "Wake on LAN", "Power On by
# PCI-E", or "Resume by LAN"), and any "ErP"/"EuP" power-saving option
# should be checked -- if enabled, it can cut power to the NIC entirely
# when the machine is off, which defeats WoL regardless of the OS-side
# settings below. That's a physical, per-machine, next-boot step -- see
# infra/jumpbox/wake-cluster.ps1's header comment and the Vikunja backlog
# item for the full checklist.
#
# What this script does on the OS side:
#   1. Detects the interface carrying the default route (works for both
#      control-plane-01's eno1 and gpu-node-01's enp6s0 without needing to
#      hardcode either).
#   2. Applies `wol g` (magic packet) immediately via ethtool.
#   3. Persists it: if NetworkManager manages the interface (it does on
#      both nodes today -- confirmed via `nmcli device status` during the
#      2026-08-23 network promotion work), sets the wake-on-lan property
#      on that connection profile, which NetworkManager re-applies on
#      every activation. Falls back to a small systemd oneshot service if
#      NetworkManager isn't managing it.
#
# Run with sudo on the target node, once each machine's BIOS WoL setting
# has been confirmed:
#   sudo bash infra/bootstrap/enable-wol.sh

set -euo pipefail

IFACE=$(ip -4 route show default | awk '{print $5; exit}')
if [ -z "$IFACE" ]; then
  echo "Could not detect the default-route interface. Pass it explicitly:" >&2
  echo "  sudo IFACE=eno1 bash infra/bootstrap/enable-wol.sh" >&2
  exit 1
fi
echo "==> Using interface: $IFACE"

echo "==> Applying wol g (magic packet) immediately"
ethtool -s "$IFACE" wol g

NM_CONN=$(nmcli -t -f DEVICE,CONNECTION device status | awk -F: -v i="$IFACE" '$1==i {print $2}')

if [ -n "$NM_CONN" ] && [ "$NM_CONN" != "--" ]; then
  echo "==> $IFACE is managed by NetworkManager (connection: $NM_CONN) -- persisting there"
  nmcli connection modify "$NM_CONN" 802-3-ethernet.wake-on-lan magic
  echo "==> Re-activating the connection to confirm the setting applies cleanly"
  nmcli connection up "$NM_CONN"
else
  echo "==> $IFACE is not NetworkManager-managed -- installing a systemd oneshot fallback"
  cat > /etc/systemd/system/wol-"$IFACE".service <<EOF
[Unit]
Description=Re-apply Wake-on-LAN (magic packet) on $IFACE at boot
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/sbin/ethtool -s $IFACE wol g

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now wol-"$IFACE".service
fi

echo
echo "==> Current Wake-on setting:"
ethtool "$IFACE" | grep -i wake-on

echo
echo "Done. Confirm BIOS/UEFI Wake-on-LAN is also enabled on this machine before relying on this."
