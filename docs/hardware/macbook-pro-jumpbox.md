# MacBook Pro — Second Admin / Jump Box

A second admin/jump box alongside the [Dell G5](dell-g5.md), added so cluster access isn't limited to a single machine. Runs **macOS**, not Windows — uses the standard OpenSSH client (`ssh`, `ssh-copy-id`) instead of PowerShell's built-in client.

## Specs

| Field | Value |
|---|---|
| OS | macOS (Darwin) |
| Hostname | `Savithris-MacBook-Pro.local` |
| SSH client | Native OpenSSH (`/usr/bin/ssh`) |
| IP | Not reserved — jump box doesn't need a static IP to reach the cluster nodes, only the reverse would (same reasoning as the Dell G5) |

## Bootstrap log

| Date | Change | Notes |
|---|---|---|
| 2026-08-18 | Generated a separate `homelab_ed25519` keypair (comment `deepesh@savi-mac`), no passphrase | Independent keypair from the Dell G5's — not copied between machines, each jump box has its own |
| 2026-08-18 (or earlier) | Key-based login already working to `gpu-node-01` and `control-plane-01` (both its wired `.47` and Wi-Fi `.106` addresses) | Predates this doc; confirmed live during the 2026-08-26 session below |
| 2026-08-26 | Authorized this Mac's key on `infra-node-01` (`ssh-copy-id`, password auth — that node hadn't been hardened to key-only yet) | Confirmed passwordless login after |
| 2026-08-26 | Fixed `~/.ssh/config`: `control-plane-01` alias now points at the wired-primary IP `192.168.0.47` (was still on the stale Wi-Fi `.106`, per `docs/decisions/0016`); added a `control-plane-01-wifi` fallback alias for `.106`; added an `infra-node-01` alias for `192.168.0.82` | Mirrors the alias set already in use from the Dell G5 |

## Role

**Not part of the Kubernetes cluster**, same as the Dell G5. A second, independent way to:

- SSH into all three non-cluster-joined-by-choice-or-role nodes: `ssh gpu-node-01`, `ssh control-plane-01` (wired, primary), `ssh control-plane-01-wifi` (fallback), `ssh infra-node-01`
- Install/manage software on the cluster (kubectl, helm, etc. — run via SSH on `control-plane-01`, same pattern as the Dell G5; no local kubeconfig is set up)
- Access apps running on the cluster from a browser

Kept deliberately independent from the Dell G5's keypair and SSH config — no shared state between the two jump boxes, so either one working doesn't depend on the other.
