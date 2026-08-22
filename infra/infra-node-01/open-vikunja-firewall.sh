#!/usr/bin/env bash
# infra/infra-node-01/open-vikunja-firewall.sh
#
# Opens the ufw port Vikunja needs: 3456/tcp for the web UI/API.
# See docs/decisions/0013 and infra/infra-node-01/vikunja/README section
# in the top-level infra-node-01 README.
#
# Run with sudo on infra-node-01:
#   sudo bash infra/infra-node-01/open-vikunja-firewall.sh

set -euo pipefail

echo "==> Opening Vikunja web UI/API port"
ufw allow 3456/tcp

echo
ufw status verbose
