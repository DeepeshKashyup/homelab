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

set -euo pipefail

echo "==> Configuring k3s containerd to use the NVIDIA runtime as default"
nvidia-ctk runtime configure \
  --runtime=containerd \
  --config=/var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl \
  --set-as-default

echo
echo "==> Restarting k3s-agent to pick up the new containerd config"
systemctl restart k3s-agent
systemctl is-active k3s-agent

echo
echo "Done on this node. Next, from control-plane-01, run:"
echo "  sudo k3s kubectl label node gpu-node-01 nvidia.com/gpu.present=true"
echo "  sudo k3s kubectl apply -f infra/k8s/base/nvidia-device-plugin.yaml"
echo "  sudo k3s kubectl describe node gpu-node-01 | grep -A5 Allocatable"
