# PC 2 — Control-Plane Node (HP ProDesk G5 800)

App / Kubernetes control-plane node. See [ADR 0002](../decisions/0002-gpu-and-control-plane-node-purchase.md).

> **Naming note:** the "G5" in "HP ProDesk G5 800" is a coincidence — this is *not* the same machine as the original Dell G5 baseline node ([`dell-g5.md`](dell-g5.md)). Use unambiguous hostnames when bootstrapping.

## Specs

| Field | Value |
|---|---|
| Model | HP ProDesk G5 800 |
| CPU | Intel i5 |
| RAM | 32GB DDR4 |
| Storage | 1TB SSD |
| Purchase price | _TBD — not recorded_ |
| OS | Ubuntu (version TBD — confirm with `lsb_release -a`) |
| Hostname | `control-plane-01` (renamed from generic `homelab-01`) |
| NIC | USB Wi-Fi adapter |
| MAC | `00:1f:05:62:9a:a6` |
| Static IP | `192.168.0.106` (DHCP reservation set on router) |

## Bootstrap log

| Date | Change | Notes |
|---|---|---|
| 2026-08-16 | Confirmed network identity | SSH not yet installed; connecting over Wi-Fi (USB adapter) — consider wired for a control-plane node's reliability |
| 2026-08-16 | Renamed hostname `homelab-01` → `control-plane-01` | Avoids confusion with the "G5" naming collision noted above |
| 2026-08-16 | Installed & enabled OpenSSH server, ufw allowing OpenSSH | Confirmed reachable on :22 from PC 1 (banner: OpenSSH_10.2p1 Ubuntu-2ubuntu3.5) |
| 2026-08-16 | Router DHCP reservation set (MAC → `192.168.0.106`) | IP is now static |
| 2026-08-16 | Key-based SSH from Dell G5 jump box confirmed; hardened via inline `sshd_config.d` drop-in (same content as `harden-ssh.sh`) | Password auth + root login disabled, key-only, no lockout |

## Role in cluster

Kubernetes control plane + general app workloads. Kept separate from the GPU node for workload isolation.
