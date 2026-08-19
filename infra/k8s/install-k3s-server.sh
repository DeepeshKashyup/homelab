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
#
# Also pins CoreDNS's upstream resolver to 1.1.1.1/8.8.8.8 instead of
# whatever the node's DHCP-provided DNS servers are. control-plane-01's
# Wi-Fi adapter got 4 DNS servers via DHCP (2 IPv4, 2 IPv6); k3s can only
# carry 3 in CoreDNS's forward config (glibc resolv.conf limit — look for
# "Nameserver limits exceeded" in `journalctl -u k3s` if this recurs), and
# kept an IPv6 one with no real route on this network. CoreDNS's forward
# plugin stalled on it before failing over, so every in-cluster external
# DNS lookup (e.g. an `ollama pull`) timed out even though the node itself
# resolved fine via systemd-resolved. Pinning to known-reachable public
# resolvers sidesteps whatever the network's DHCP happens to hand out.

set -euo pipefail

echo "==> Pinning CoreDNS's upstream DNS to 1.1.1.1 / 8.8.8.8"
mkdir -p /etc/rancher/k3s
cat <<'EOF' > /etc/rancher/k3s/resolv.conf
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
if [ ! -f /etc/rancher/k3s/config.yaml ] || ! grep -q '^resolv-conf:' /etc/rancher/k3s/config.yaml; then
  echo "resolv-conf: /etc/rancher/k3s/resolv.conf" >> /etc/rancher/k3s/config.yaml
fi

echo
echo "==> Installing k3s server (bundled flannel CNI, node IP auto-detected)"
curl -sfL https://get.k3s.io | sh -

echo
echo "==> Restarting k3s to pick up the resolv-conf setting (no-op on a fresh install)"
systemctl restart k3s

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
