#!/usr/bin/env bash
# infra/k8s/open-nodeport-firewall.sh
#
# Opens the NodePort range used by the ollama-openwebui deployment
# (infra/k8s/base/ollama-openwebui/) in ufw. See docs/decisions/0009 —
# access currently works without this (NodePort traffic appears to bypass
# ufw's filter chain via kube-proxy's DNAT), but that's incidental
# behavior, not something to rely on. Run on BOTH nodes: NodePort Services
# are reachable via any node's IP regardless of which node the pod runs
# on, so both control-plane-01 and gpu-node-01 need these rules.
#
# Run with sudo:
#   sudo bash infra/k8s/open-nodeport-firewall.sh

set -euo pipefail

echo "==> Opening NodePort ports used by ollama-openwebui"
ufw allow 30080/tcp   # Open WebUI
ufw allow 31434/tcp   # Ollama API

echo
ufw status verbose
