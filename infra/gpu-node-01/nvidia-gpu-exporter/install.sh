#!/usr/bin/env bash
# infra/gpu-node-01/nvidia-gpu-exporter/install.sh
#
# Installs utkuozdemir/nvidia_gpu_exporter (v1.14.0) via its .deb package,
# which ships its own systemd unit — nothing to hand-write here, unlike
# gpu-temp-exporter/. See README.md in this directory for why this runs as
# a host systemd service instead of a Kubernetes workload (nvidia.com/gpu
# device-plugin contention with the Ollama/ComfyUI toggle).
#
# Run with sudo on gpu-node-01:
#   sudo bash infra/gpu-node-01/nvidia-gpu-exporter/install.sh

set -euo pipefail

VERSION="1.14.0"
DEB="nvidia-gpu-exporter_${VERSION}_linux_amd64.deb"
URL="https://github.com/utkuozdemir/nvidia_gpu_exporter/releases/download/v${VERSION}/${DEB}"

if systemctl is-active --quiet nvidia_gpu_exporter 2>/dev/null; then
  echo "==> nvidia_gpu_exporter already running, skipping install"
else
  echo "==> Downloading ${DEB}"
  curl -fsSL -o "/tmp/${DEB}" "$URL"

  echo "==> Installing"
  dpkg -i "/tmp/${DEB}"
  rm "/tmp/${DEB}"

  echo "==> Enabling service"
  systemctl enable --now nvidia_gpu_exporter
fi

echo "==> Opening firewall (9835/tcp — not covered by the NodePort range or k3s rules)"
ufw allow 9835/tcp

echo
echo "==> Verifying"
sleep 1
curl -fsS http://localhost:9835/metrics | grep -E '^nvidia_smi_(temperature_gpu|power_draw_watts|memory_used_bytes) '

echo
echo "Done. From the LAN: curl http://192.168.0.79:9835/metrics"
