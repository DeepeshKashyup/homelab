#!/usr/bin/env bash
# infra/k8s/open-nodeport-firewall.sh
#
# Opens the standard Kubernetes NodePort range in ufw. Both
# install-k3s-server.sh and join-k3s-agent.sh do this automatically now —
# this script exists as a standalone fixer for a node that was set up
# before that, without needing to re-run the full install/join flow.
#
# Run with sudo on any node:
#   sudo bash infra/k8s/open-nodeport-firewall.sh

set -euo pipefail

echo "==> Opening the Kubernetes NodePort range in ufw"
ufw allow 30000:32767/tcp

echo
ufw status verbose
