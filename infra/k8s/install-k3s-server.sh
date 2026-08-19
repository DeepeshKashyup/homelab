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
#
# Also opens the ufw ports a worker node needs to join and stay connected
# (6443/8472/10250). install-ssh.sh only ever opened OpenSSH, so without
# this a worker's k3s-agent silently hangs retrying "Failed to validate
# connection to cluster ... context deadline exceeded" forever instead of
# failing loudly — that's what happened joining gpu-node-01 the first time.

set -euo pipefail

echo "==> Installing k3s server (bundled flannel CNI, node IP auto-detected)"
curl -sfL https://get.k3s.io | sh -

echo
echo "==> Opening firewall ports needed by worker nodes"
ufw allow 6443/tcp    # k3s API server (workers register/authenticate here)
ufw allow 8472/udp    # flannel VXLAN overlay (pod-to-pod traffic between nodes)
ufw allow 10250/tcp   # kubelet API (control-plane <-> node metrics/exec)
ufw status verbose

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
