#!/usr/bin/env bash
# infra/k8s/install-k3s-server.sh
#
# Installs k3s as the control-plane server on this node, using the bundled
# flannel CNI (see docs/decisions/0007-flannel-then-cilium.md — Cilium
# migration is a deliberate later step, not part of this script).
#
# Run with sudo on control-plane-01:
#   sudo bash infra/k8s/install-k3s-server.sh
#
# After this completes:
#   - kubectl (via k3s) is usable locally as root: k3s kubectl get nodes
#   - kubeconfig is at /etc/rancher/k3s/k3s.yaml
#   - the node token needed to join gpu-node-01 as a worker is printed at
#     the end and saved at /var/lib/rancher/k3s/server/node-token

set -euo pipefail

echo "==> Installing k3s server (bundled flannel CNI, node IP auto-detected)"
curl -sfL https://get.k3s.io | sh -

echo
echo "==> k3s service status"
systemctl is-active k3s
systemctl is-enabled k3s

echo
echo "==> Cluster node list"
k3s kubectl get nodes -o wide

echo
echo "==> Node token (needed on gpu-node-01 to join as a worker)"
echo "    Also saved at /var/lib/rancher/k3s/server/node-token"
cat /var/lib/rancher/k3s/server/node-token

echo
echo "Done. Next: on gpu-node-01, run infra/k8s/join-k3s-agent.sh with this"
echo "node's IP and the token above."
