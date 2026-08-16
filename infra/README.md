# infra/

Infrastructure for the homelab platform.

- **`bootstrap/`** — one-time node prep: OS hardening, SSH setup, base packages, NVIDIA drivers/container toolkit. Run before a node joins the cluster.
- **`k8s/`** — Kubernetes manifests.
  - `base/` — core cluster components (Cilium CNI, CloudNativePG, GPU device plugin, ML serving workloads).
  - `overlays/` — environment-specific overrides (e.g. per-node GPU scheduling, resource limits).
