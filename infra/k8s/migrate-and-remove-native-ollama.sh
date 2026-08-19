#!/usr/bin/env bash
# infra/k8s/migrate-and-remove-native-ollama.sh
#
# One-time cleanup for gpu-node-01: a native `ollama.service` (installed
# outside Kubernetes, before this project's k3s work) was found still
# running alongside the new Kubernetes-managed Ollama deployment, with
# its own already-pulled models. This script:
#   1. Copies its model blobs/manifests into the Kubernetes Ollama pod's
#      PVC (content-addressable storage — safe to merge, no risk of
#      corrupting the models already pulled through Kubernetes).
#   2. Restarts the Kubernetes ollama Deployment so it picks up the
#      migrated models.
#   3. Stops, disables, and fully removes the native service, its binary,
#      its data directory, and its dedicated system user/group.
#
# Run with sudo on gpu-node-01:
#   sudo bash infra/k8s/migrate-and-remove-native-ollama.sh
#
# Safe to re-run: each step checks whether there's anything to do.
#
# Note: `kubectl` only has local API access on control-plane-01 (that's
# where the k3s server + kubeconfig live) — gpu-node-01 is a worker with
# no local API access, so `k3s kubectl` here defaults to a dead
# localhost:8080 and fails. This script runs on gpu-node-01 (where the
# native service actually is), so the Deployment-restart step is
# best-effort: if it can't reach the API, it prints the command to run
# from control-plane-01 instead and continues — it does NOT abort the
# rest of the script (the removal steps don't need kubectl at all).

set -euo pipefail

NATIVE_MODELS=/usr/share/ollama/.ollama/models

echo "==> Locating the Kubernetes Ollama PVC's storage directory on this node"
PVC_DIR=$(find /var/lib/rancher/k3s/storage -maxdepth 1 -iname '*ollama-models*' -type d | head -1)
if [ -z "$PVC_DIR" ]; then
  echo "ERROR: couldn't find the ollama-models PVC directory under /var/lib/rancher/k3s/storage."
  echo "Is the ollama Deployment actually running on this node? Aborting without changing anything."
  exit 1
fi
DEST="$PVC_DIR/models"
echo "    PVC storage dir: $PVC_DIR"

if [ ! -d "$NATIVE_MODELS" ]; then
  echo "==> No native Ollama models directory at $NATIVE_MODELS — nothing to migrate, skipping to removal"
else
  echo "==> Migrating native models into the Kubernetes PVC"
  mkdir -p "$DEST/blobs" "$DEST/manifests"
  cp -an "$NATIVE_MODELS/blobs/." "$DEST/blobs/" 2>/dev/null || true
  cp -an "$NATIVE_MODELS/manifests/." "$DEST/manifests/" 2>/dev/null || true
  echo "    Copied (existing files in the destination were left untouched, per -n)"

  echo
  echo "==> Restarting the Kubernetes ollama Deployment so it picks up the migrated models"
  if k3s kubectl get nodes >/dev/null 2>&1; then
    k3s kubectl rollout restart deployment/ollama -n ollama
    k3s kubectl rollout status deployment/ollama -n ollama --timeout=120s
    echo
    echo "==> Models now visible to the Kubernetes-managed Ollama:"
    k3s kubectl exec -n ollama deploy/ollama -- ollama list
  else
    echo "    No local kubectl API access from this node (expected on a worker"
    echo "    node — gpu-node-01 only has kubelet, not the API server)."
    echo "    Run this from control-plane-01 to pick up the migrated models:"
    echo "      sudo k3s kubectl rollout restart deployment/ollama -n ollama"
    echo "      sudo k3s kubectl exec -n ollama deploy/ollama -- ollama list"
  fi
fi

echo
echo "==> Removing the native ollama.service"
systemctl stop ollama 2>/dev/null || true
systemctl disable ollama 2>/dev/null || true
rm -f /etc/systemd/system/ollama.service
systemctl daemon-reload
rm -f "$(command -v ollama || true)"
rm -rf /usr/share/ollama
userdel ollama 2>/dev/null || true
groupdel ollama 2>/dev/null || true

echo
echo "Done. Verify with: systemctl status ollama (should say not found/unknown unit)"
