# k8s/

Kubernetes manifests for the cluster.

- **`base/`** — core components shared across the cluster: Cilium CNI, CloudNativePG, GPU device plugin/scheduling, Ollama, Open-WebUI.
- **`overlays/`** — per-environment or per-node overrides (Kustomize-style), e.g. GPU node taints/tolerations, resource limits tuned to the Dell G5 / GTX 1060 baseline.

Nothing here yet — cluster install comes after node bootstrap ([`infra/bootstrap/`](../bootstrap/)) is complete.
