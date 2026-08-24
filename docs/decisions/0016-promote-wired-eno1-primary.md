# ADR 0016: Promote control-plane-01's Wired eno1 to Primary Identity

**Status:** Accepted
**Date:** 2026-08-23
**Related to:** [ADR 0014](0014-wired-ethernet-and-shared-storage-for-distributed-workloads.md) (this closes that ADR's "promote `.47`" follow-up)

## Context

While starting today's Postgres/CloudNativePG work, the `control-plane-01` SSH alias (`192.168.0.106`, Wi-Fi) timed out. Investigation found:

- `control-plane-01`'s Wi-Fi interface (`wlx001f05629aa6`) was disconnected. Its wired `eno1` (`192.168.0.47`, plain DHCP, added per ADR 0014 for the Plex bulk-transfer fix but never promoted) was up and reachable.
- More significantly: **k3s was advertising `control-plane-01`'s `INTERNAL-IP` as `192.168.0.106`** (`kubectl get nodes -o wide`), set automatically at install time before `eno1` was ever connected. This wasn't just a jump-box inconvenience — flannel's cross-node overlay routing to this node's pods depends on that advertised IP being reachable. With Wi-Fi down, any node trying to reach `control-plane-01` over the pod network would have failed, independent of that other node's own health.
- `gpu-node-01` was separately found unreachable (even from `control-plane-01` itself, at the ARP level) — a real, unrelated problem (no Wi-Fi/Ethernet distinction involved; it's fully wired already), tracked separately and out of scope here.

ADR 0014 had already flagged promoting `.47` as "a formal requirement," deferred as "a bigger, more careful change." This incident made it urgent rather than optional.

## Decision

Promote `eno1` (`192.168.0.47`) to `control-plane-01`'s primary network identity, keeping the same address (no renumbering):

1. Pin DNS on `eno1` to `1.1.1.1`/`8.8.8.8` in netplan (same reasoning as ADR 0010) — addressing itself stays DHCP.
2. Set `node-ip: 192.168.0.47` in `/etc/rancher/k3s/config.yaml` and restart k3s, so k3s advertises the correct, currently-working interface.
3. Update the Dell G5's `~/.ssh/config`: `control-plane-01` now points at `.47`; the old Wi-Fi address is kept as a separate `control-plane-01-wifi` alias rather than deleted outright.
4. Update docs/READMEs that hardcoded `.106` as the access URL (Open WebUI, ComfyUI, Plex, AdGuard DNS-rewrite example) to `.47`.

A router DHCP reservation for `.47` (matching the mechanism ADR 0002 used for the original static IPs) is a **pending manual step**, not yet done — today's fix reuses the currently-active DHCP lease as-is, which is stable enough for now but not guaranteed indefinitely.

## Rationale

- **This was a live bug, not speculative cleanup.** k3s advertising a down interface as a node's internal IP is a real cross-node networking failure mode, only unnoticed so far because `gpu-node-01` was separately down too.
- **Smallest safe change.** Reusing the existing `.47` lease avoids renumbering anything; only the *advertised identity* (k3s node-ip, SSH alias, docs) changes, not the address itself.
- **Matches the project's existing pattern for this exact class of problem.** ADR 0010 pinned DNS to public resolvers rather than trusting a possibly-unreliable DHCP-provided one; the same reasoning applies here to `eno1`'s DNS.
- **`gpu-node-01`'s equivalent fix is deferred, not forgotten.** It's unreachable right now, so its own k3s agent config (`server:` field, if it still points at `.106`) can't be checked or fixed today — tracked as a follow-up for when it's physically back online.

## Consequences

- `control-plane-01`'s Wi-Fi is now explicitly the fallback path, not primary — if `eno1`/the wired switch ever goes down, the node becomes unreachable by IP unless Wi-Fi is manually reconnected (no automatic failover configured).
- Every doc/README pointing LAN access at `192.168.0.106` (Open WebUI, ComfyUI, Plex, the AdGuard DNS-rewrite example) now points at `.47` instead. Any bookmark, remote-access router port-forward rule, or script outside this repo that still hardcodes `.106` needs updating separately — this ADR only covers what's in the repo.
- The k3s restart needed to apply `node-ip` briefly interrupted control-plane API availability; already-running pods (Open WebUI, Plex) kept running under containerd throughout and needed no manual recovery.
- `.47`'s address is still a DHCP lease, not a reservation — a router restart or lease expiry could theoretically reassign it before the reservation follow-up is done.

## Follow-ups

- [ ] Add the router DHCP reservation for `.47` (MAC `e8:d8:d1:b9:06:f3`) — manual step, not yet done.
- [ ] Once `gpu-node-01` is physically back online, check its k3s agent config's `server:` field and update from `.106` to `.47` if needed, then restart `k3s-agent`.
- [ ] Investigate why `gpu-node-01` went unreachable (separate from this ADR) — physical check needed, no Wake-on-LAN configured.
- [ ] Confirm the Plex remote-access router port-forward (if already configured) has been updated from `.106` to `.47`.
