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
#
# Also opens the ufw ports needed for cross-node cluster traffic TO this
# node (flannel VXLAN, kubelet API, NodePort range). Without this, traffic
# FROM control-plane-01 TO this node is silently dropped even though the
# reverse direction works fine — install-k3s-server.sh only ever opened
# control-plane-01's firewall, this node's was never touched. That
# asymmetry meant Ollama (running here) was completely unreachable via its
# ClusterIP/NodePort from control-plane-01 or anywhere else off this node,
# even though the pod itself was healthy — see docs/decisions/0011 for the
# full incident writeup.

set -euo pipefail

: "${K3S_URL:?Set K3S_URL=https://<control-plane-ip>:6443}"
: "${K3S_TOKEN:?Set K3S_TOKEN=<node-token from control-plane-01>}"

echo "==> Joining k3s cluster at ${K3S_URL}"
curl -sfL https://get.k3s.io | sh -

echo
echo "==> Opening firewall ports needed for cross-node cluster traffic"
ufw allow 8472/udp        # flannel VXLAN overlay (pod-to-pod traffic between nodes)
ufw allow 10250/tcp       # kubelet API (control-plane <-> node metrics/exec)
ufw allow 30000:32767/tcp # NodePort range (any Service exposed via NodePort, e.g. Ollama)
ufw status verbose

echo
echo "==> k3s-agent service status"
systemctl is-active k3s-agent
systemctl is-enabled k3s-agent

echo
echo "Done. Verify from control-plane-01 with: k3s kubectl get nodes -o wide"
