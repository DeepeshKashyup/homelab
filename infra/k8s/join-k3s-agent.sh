#!/usr/bin/env bash
# infra/k8s/join-k3s-agent.sh
#
# Joins this node to an existing k3s cluster as a worker (agent).
# Intended for gpu-node-01, joining control-plane-01.
#
# Do NOT run until install-k3s-server.sh has completed successfully on the
# control plane and its node status is Ready.
#
# Run with sudo on gpu-node-01, passing the control-plane IP and node token
# printed by install-k3s-server.sh:
#   sudo K3S_URL=https://<control-plane-ip>:6443 \
#        K3S_TOKEN=<node-token> \
#        bash infra/k8s/join-k3s-agent.sh

set -euo pipefail

: "${K3S_URL:?Set K3S_URL=https://<control-plane-ip>:6443}"
: "${K3S_TOKEN:?Set K3S_TOKEN=<node-token from control-plane-01>}"

echo "==> Joining k3s cluster at ${K3S_URL}"
curl -sfL https://get.k3s.io | sh -

echo
echo "==> k3s-agent service status"
systemctl is-active k3s-agent
systemctl is-enabled k3s-agent

echo
echo "Done. Verify from control-plane-01 with: k3s kubectl get nodes -o wide"
