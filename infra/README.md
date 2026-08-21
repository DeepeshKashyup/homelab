# infra/

Infrastructure for the homelab platform.

- **`bootstrap/`** — one-time node prep: OS hardening, SSH setup, base packages, NVIDIA drivers/container toolkit. Run before a node joins the cluster (or, for `infra-node-01`, before it runs anything at all — it never joins the k3s cluster, see ADR 0013).
- **`k8s/`** — Kubernetes manifests and cluster install scripts, for `control-plane-01`/`gpu-node-01` only.
  - `base/` — core cluster components (CNI, GPU device plugin, ML serving workloads).
  - `overlays/` — environment-specific overrides (e.g. per-node GPU scheduling, resource limits).
- **`infra-node-01/`** — Docker-based services running directly on `infra-node-01` (AdGuard Home for local DNS, and future small always-on services). Not Kubernetes — see [ADR 0013](../docs/decisions/0013-infra-node-dedicated-services-adguard-dns.md).
- **`jumpbox/`** — scripts run *from* the Dell G5 jump box (PowerShell) rather than on a node.
