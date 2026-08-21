#!/usr/bin/env bash
# infra/infra-node-01/open-dns-firewall.sh
#
# Opens the ufw ports AdGuard Home needs: 53/tcp+udp for DNS itself,
# 3000/tcp for the admin web UI. See docs/decisions/0013.
#
# Run with sudo on infra-node-01:
#   sudo bash infra/infra-node-01/open-dns-firewall.sh

set -euo pipefail

echo "==> Opening DNS + AdGuard Home admin UI ports"
ufw allow 53/tcp
ufw allow 53/udp
ufw allow 3000/tcp

echo
ufw status verbose
