#!/usr/bin/env bash
# infra/infra-node-01/open-dns-firewall.sh
#
# Opens the ufw ports AdGuard Home needs: 53/tcp+udp for DNS itself,
# 3000/tcp for the first-run setup wizard, 80/tcp for the admin web UI
# post-setup (AdGuard Home switched to 80 during setup on this
# deployment, despite the wizard defaulting to offer 3000). See
# docs/decisions/0013.
#
# Run with sudo on infra-node-01:
#   sudo bash infra/infra-node-01/open-dns-firewall.sh

set -euo pipefail

echo "==> Opening DNS + AdGuard Home admin UI ports"
ufw allow 53/tcp
ufw allow 53/udp
ufw allow 3000/tcp
ufw allow 80/tcp

echo
ufw status verbose
