# k8s/

Cluster install scripts and Kubernetes manifests.

- **`install-k3s-server.sh`** — installs k3s as the control-plane server (bundled flannel CNI; see [ADR 0007](../../docs/decisions/0007-flannel-then-cilium.md)). Run on `control-plane-01`.
- **`join-k3s-agent.sh`** — joins a node to the cluster as a worker. Run on `gpu-node-01` after the server script has completed and reports `Ready`.
- **`base/`** — core components shared across the cluster: Cilium CNI, CloudNativePG, GPU device plugin/scheduling, Ollama, Open-WebUI. Nothing here yet.
- **`overlays/`** — per-environment or per-node overrides (Kustomize-style), e.g. GPU node taints/tolerations, resource limits tuned to the Dell G5 / GTX 1060 baseline. Nothing here yet.

Manifests come after both nodes have joined the cluster and `kubectl get nodes` is healthy. Node bootstrap ([`infra/bootstrap/`](../bootstrap/)) must be complete before running the scripts here.
