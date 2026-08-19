# k8s/

Cluster install scripts and Kubernetes manifests.

- **`install-k3s-server.sh`** — installs k3s as the control-plane server (bundled flannel CNI; see [ADR 0007](../../docs/decisions/0007-flannel-then-cilium.md)). Run on `control-plane-01`.
- **`join-k3s-agent.sh`** — joins a node to the cluster as a worker. Run on `gpu-node-01` after the server script has completed and reports `Ready`.
- **`configure-nvidia-runtime.sh`** — wires `nvidia-container-toolkit` into k3s's containerd as the default runtime and labels the node for GPU scheduling (see [ADR 0008](../../docs/decisions/0008-nvidia-device-plugin-default-runtime.md)). Run on `gpu-node-01`.
- **`base/`** — core components shared across the cluster.
  - `nvidia-device-plugin.yaml` — NVIDIA device plugin DaemonSet, vendored from upstream, scoped to `gpu-node-01` via `nodeSelector`.
  - `ollama-openwebui/` — Ollama (GPU-scheduled) + Open WebUI, exposed via NodePort (see [ADR 0009](../../docs/decisions/0009-nodeport-then-traefik-ingress.md)). See its own README for apply/access instructions.
  - Still to add: Cilium CNI, CloudNativePG.
- **`smoke-tests/`** — one-shot validation pods, applied and deleted manually, not part of the standing cluster state (e.g. `gpu-smoke-test.yaml`).
- **`overlays/`** — per-environment or per-node overrides (Kustomize-style), e.g. GPU node taints/tolerations, resource limits tuned to the Dell G5 / GTX 1060 baseline. Nothing here yet.

Manifests come after both nodes have joined the cluster and `kubectl get nodes` is healthy. Node bootstrap ([`infra/bootstrap/`](../bootstrap/)) must be complete before running the scripts here.
