# Dell G5 — Admin / Jump Box

Original baseline compute node for the homelab platform. Runs **Windows**, not Linux — different from PC 1 / PC 2, which changes the tooling used on it (PowerShell + built-in Windows OpenSSH client, no `ssh-copy-id`, `icacls` instead of `chmod`).

## Specs

| Field | Value |
|---|---|
| GPU | GTX 1060 |
| CPU | _TBD_ |
| RAM | _TBD_ |
| Storage | _TBD_ |
| OS | Windows (version TBD) |
| SSH client | Built-in Windows OpenSSH (PowerShell) |
| Hostname | _TBD_ |
| IP | _TBD — not reserved yet; jump box doesn't need a static IP to reach the cluster nodes, only the reverse would_ |

## Bootstrap log

| Date | Change | Notes |
|---|---|---|
| 2026-08-16 | Generated `homelab_ed25519` keypair; copied to PC 1 and PC 2 | No passphrase set — convenience over the jump box's own LAN-local risk profile |
| 2026-08-16 | Confirmed key-based login to both nodes, no password prompt | |
| 2026-08-16 | Added `~/.ssh/config` with `gpu-node-01` / `control-plane-01` host aliases | Hit "Bad permissions" from OpenSSH — `Set-Content` inherited broad ACLs from the parent folder. Fixed with `icacls "$env:USERPROFILE\.ssh\config" /inheritance:r` + `/grant:r "$env:USERNAME:F"`. Both aliases confirmed working after. |

## Role

**Not part of the Kubernetes cluster.** Original baseline node, repurposed as the admin/jump box now that [PC 1 (GPU node) and PC 2 (control plane)](../decisions/0002-gpu-and-control-plane-node-purchase.md) handle cluster duties. Used to:

- SSH into cluster nodes
- Install/manage software on the cluster (kubectl, helm, etc.)
- Access apps running on the cluster
