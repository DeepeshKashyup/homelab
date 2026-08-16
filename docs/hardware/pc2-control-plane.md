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
| OS | Ubuntu Server (planned) |
| Hostname | _TBD_ |
| Static IP | _TBD_ |

## Bootstrap log

| Date | Change | Notes |
|---|---|---|
| | | |

## Role in cluster

Kubernetes control plane + general app workloads. Kept separate from the GPU node for workload isolation.
