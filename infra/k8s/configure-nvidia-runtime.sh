#!/usr/bin/env bash
# infra/k8s/configure-nvidia-runtime.sh
#
# Wires the already-installed nvidia-container-toolkit into k3s's embedded
# containerd on a GPU worker node, makes it the default runtime for that
# node, and labels the node so the device plugin DaemonSet
# (infra/k8s/base/nvidia-device-plugin.yaml) knows to schedule there.
#
# See docs/decisions/0008-nvidia-device-plugin-default-runtime.md for why
# this uses --set-as-default instead of a RuntimeClass.
#
# Prerequisites: nvidia-container-toolkit already installed (nvidia-ctk on
# PATH), node already joined to the cluster as a k3s agent.
#
# Run with sudo on gpu-node-01:
#   sudo bash infra/k8s/configure-nvidia-runtime.sh
#
# The node label step runs kubectl against the control plane, so it needs
# a working kubeconfig — run it from control-plane-01 if gpu-node-01 has
# no kubeconfig of its own (see the two-part instructions printed below).
#
# IMPORTANT: config.toml.tmpl must be seeded from k3s's own generated
# config.toml before nvidia-ctk touches it. If config.toml.tmpl doesn't
# exist yet, nvidia-ctk creates one from containerd's generic defaults —
# which lack the CNI bin/conf dir paths and CRI settings k3s needs. Once
# k3s regenerates config.toml from that generic template, its CRI plugin
# can no longer initialize the CNI (flannel) plugin, and kubelet loops
# forever on "cni plugin not initialized" — this actually happened
# bringing up gpu-node-01. Seeding the template first (below) avoids it.

set -euo pipefail

CONFIG_TOML="/var/lib/rancher/k3s/agent/etc/containerd/config.toml"
CONFIG_TMPL="/var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl"

if [ ! -f "$CONFIG_TOML" ]; then
  echo "ERROR: $CONFIG_TOML not found — is k3s-agent installed and has it run at least once?"
  exit 1
fi

echo "==> Seeding containerd config template from k3s's own generated config"
echo "    (preserves k3s's CNI/CRI settings; see note above on why this matters)"
cp "$CONFIG_TOML" "$CONFIG_TMPL"

echo
echo "==> Configuring k3s containerd to use the NVIDIA runtime as default"
nvidia-ctk runtime configure \
  --runtime=containerd \
  --config="$CONFIG_TMPL" \
  --set-as-default

echo
echo "==> Restarting k3s-agent to pick up the new containerd config"
systemctl restart k3s-agent
systemctl is-active k3s-agent

echo
echo "==> Confirming CNI came up healthy (should show no repeating errors below)"
sleep 3
journalctl -u k3s-agent --no-pager -n 10 | grep -i "cni plugin not initialized" \
  && { echo "WARNING: CNI not initialized — do not proceed, see script header for recovery steps"; exit 1; } \
  || echo "OK: no CNI errors in recent logs"

echo
echo "Done on this node. Next, from control-plane-01, run:"
echo "  sudo k3s kubectl label node gpu-node-01 nvidia.com/gpu.present=true"
echo "  sudo k3s kubectl apply -f infra/k8s/base/nvidia-device-plugin.yaml"
echo "  sudo k3s kubectl describe node gpu-node-01 | grep -A5 Allocatable"
