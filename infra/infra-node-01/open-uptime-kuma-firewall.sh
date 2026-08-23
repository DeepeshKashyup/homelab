#!/usr/bin/env bash
# infra/infra-node-01/open-uptime-kuma-firewall.sh
#
# Opens the ufw port Uptime Kuma needs: 3001/tcp for the web UI.
# See docs/decisions/0013 and the infra-node-01 README's Uptime Kuma
# section.
#
# Run with sudo on infra-node-01:
#   sudo bash infra/infra-node-01/open-uptime-kuma-firewall.sh

set -euo pipefail

echo "==> Opening Uptime Kuma web UI port"
ufw allow 3001/tcp

echo
ufw status verbose
