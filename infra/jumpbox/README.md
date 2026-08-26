# jumpbox/

Scripts meant to run **from a jump box**, not on the cluster nodes themselves — everything else under `infra/` runs on `control-plane-01`/`gpu-node-01` directly.

There are now two independent jump boxes (see `docs/hardware/dell-g5.md` and `docs/hardware/macbook-pro-jumpbox.md`), each with its own `homelab_ed25519` keypair and `~/.ssh/config` aliases (`gpu-node-01`, `control-plane-01`, `control-plane-01-wifi`, `infra-node-01`) — no shared state between them. The `.ps1` scripts below are Dell G5 (PowerShell)-specific; the MacBook Pro jump box runs the equivalent commands directly in a shell (`ssh gpu-node-01 sudo shutdown -h now`, etc.) rather than via a script, since there's nothing PowerShell-specific to work around on macOS.

Keep `.ps1` files here plain ASCII (no em-dashes, smart quotes, etc.) — Windows PowerShell 5.1 can misparse UTF-8-without-BOM files containing non-ASCII characters under some console codepages, throwing a confusing `"The string is missing the terminator"` error that has nothing to do with the actual quoting. Hit this on the first version of `shutdown-cluster.ps1`; fixed by rewriting with only ASCII.

- **`shutdown-cluster.ps1`** — shuts down both nodes over SSH (`ssh gpu-node-01`/`ssh control-plane-01` aliases). Will prompt for the `sudo` password interactively on each node, same as running the command by hand.
- **`wake-cluster.ps1`** — sends Wake-on-LAN magic packets to both nodes (`-Node control-plane-01`/`-Node gpu-node-01` to target just one). Prepared 2026-08-24 but **not usable yet** — needs BIOS/UEFI Wake-on-LAN enabled on each machine (physical, next-boot step) and [`infra/bootstrap/enable-wol.sh`](../bootstrap/enable-wol.sh) run on each node first. See the Vikunja backlog item for the full checklist.

## After a physical restart

Wake-on-LAN isn't set up yet (see `wake-cluster.ps1` above), so bringing the nodes back up today means physically powering them on. Once both are up:

1. Give it a minute or two — `k3s`/`k3s-agent` start automatically (systemd-enabled), and need a short window to reconcile.
2. Check cluster health from `control-plane-01`: `sudo k3s kubectl get nodes -o wide` — both should show `Ready`.
3. Check what's actually running: `sudo k3s kubectl get pods -A`. Whichever of Ollama/ComfyUI was scaled up when you shut down comes back up automatically (desired replica counts persist on disk) — the other stays at 0. Switch which one's active with the scale commands in [`infra/k8s/base/comfyui/README.md`](../k8s/base/comfyui/README.md) if needed.
4. All models and other PVC data persist across the reboot untouched — nothing to re-download.
