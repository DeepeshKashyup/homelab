# Dell G5 — GPU Node

Baseline compute node for the homelab platform.

## Specs

| Field | Value |
|---|---|
| GPU | GTX 1060 |
| CPU | _TBD_ |
| RAM | _TBD_ |
| Storage | _TBD_ |
| OS | Ubuntu Server (planned) |
| Hostname | _TBD_ |
| Static IP | _TBD_ |

## Bootstrap log

| Date | Change | Notes |
|---|---|---|
| | | |

## Role

**Not part of the Kubernetes cluster.** Original baseline node, repurposed as the admin/jump box now that [PC 1 (GPU node) and PC 2 (control plane)](../decisions/0002-gpu-and-control-plane-node-purchase.md) handle cluster duties. Used to:

- SSH into cluster nodes
- Install/manage software on the cluster (kubectl, helm, etc.)
- Access apps running on the cluster
