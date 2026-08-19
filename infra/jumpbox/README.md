# jumpbox/

Scripts meant to run **from the Dell G5 jump box** (PowerShell), not on the cluster nodes themselves — everything else under `infra/` runs on `control-plane-01`/`gpu-node-01` directly.

- **`shutdown-cluster.ps1`** — shuts down both nodes over SSH (`ssh gpu-node-01`/`ssh control-plane-01` aliases). Will prompt for the `sudo` password interactively on each node, same as running the command by hand.

## After a physical restart

No Wake-on-LAN is configured, so bringing the nodes back up means physically powering them on. Once both are up:

1. Give it a minute or two — `k3s`/`k3s-agent` start automatically (systemd-enabled), and need a short window to reconcile.
2. Check cluster health from `control-plane-01`: `sudo k3s kubectl get nodes -o wide` — both should show `Ready`.
3. Check what's actually running: `sudo k3s kubectl get pods -A`. Whichever of Ollama/ComfyUI was scaled up when you shut down comes back up automatically (desired replica counts persist on disk) — the other stays at 0. Switch which one's active with the scale commands in [`infra/k8s/base/comfyui/README.md`](../k8s/base/comfyui/README.md) if needed.
4. All models and other PVC data persist across the reboot untouched — nothing to re-download.
