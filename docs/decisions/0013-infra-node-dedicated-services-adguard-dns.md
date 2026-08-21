# ADR 0013: infra-node-01 — Dedicated Services Node, Not a Cluster Worker; AdGuard Home for Local DNS

**Status:** Accepted
**Date:** 2026-08-21
**Related to:** [ADR 0009](0009-nodeport-then-traefik-ingress.md) (this ADR resolves its open "decide on a local DNS approach" follow-up)

## Context

A third machine became available: a Lenovo ThinkCentre M700 Tiny (i3-6100T, 2C/4T, 35W TDP; 8GB RAM; 100GB SSD). Two decisions were needed: what role it plays in the platform, and — if that role includes local DNS — which DNS software and deployment method.

## Decision: keep it out of the k3s cluster, give it a dedicated infra/services role

The M700 will **not** join the k3s cluster as a third worker. It's set up as `infra-node-01`, a standalone Ubuntu Server box running Docker-based services directly, starting with local DNS (AdGuard Home).

## Rationale

- **Modest hardware, but real 24/7 value.** 8GB RAM and a 2C/4T CPU are underwhelming as a Kubernetes worker (barely enough for `kubelet`/`containerd` overhead plus meaningful workload headroom), but perfectly adequate for the kind of small, always-on services this node is meant to run (DNS, and later monitoring). Its 35W TDP makes it cheap to leave on 24/7 compared to the other two nodes.
- **Matches the project's incremental philosophy (ADR 0004).** Joining it to the cluster "because we have another node" adds a worker with awkward resource constraints (would need careful `nodeSelector`/taint work to avoid the scheduler placing GPU-adjacent or memory-heavy pods there) without a concrete workload driving that complexity. A dedicated role is simpler and matches what it's actually going to do.
- **Infrastructure services (DNS in particular) benefit from being independent of the cluster they help serve.** If `control-plane-01` or the whole k3s cluster is down/being rebuilt, LAN DNS resolution (and eventually monitoring of that same cluster) should keep working — that's harder to guarantee if the DNS server itself is a pod inside the thing it's monitoring/resolving for.
- Bootstrap reused the existing `infra/bootstrap/` scripts unchanged (SSH hardening, base packages) — no new node-prep tooling needed despite the new role.

## Decision: AdGuard Home, deployed via Docker

- **AdGuard Home** over Pi-hole: single Go binary, simpler operational footprint, built-in DNS-over-HTTPS/TLS to upstream resolvers without a separate component (Pi-hole needs something like `cloudflared` bolted on for the same), and a straightforward "DNS rewrites" UI for the actual goal here — local hostnames like `openwebui.homelab.local` pointing at cluster node IPs.
- **Docker** over a native install: matches the "small Docker services" role this node is meant for generally (not just DNS), and makes AdGuard Home trivial to update, reinstall, or move without touching the host OS. `infra/infra-node-01/install-docker.sh` installs Docker Engine via its official apt repository (not a curl-pipe-to-shell installer).

## Consequences

- `infra-node-01` runs outside `kubectl`'s visibility entirely — `docker compose` / `docker ps` on the node itself is how you check what's running there, not anything in this repo's `infra/k8s/`.
- Router DHCP needs to be pointed at `infra-node-01` (`192.168.0.82`) as the LAN's DNS server for AdGuard Home to actually take effect for other devices — a router config change outside this repo's scope, tracked as a follow-up.
- The Traefik Ingress migration (ADR 0009's deferred second phase) is now unblocked on the DNS side — hostnames can be added via AdGuard Home's DNS rewrites once Ingress resources exist to route them.
- Future small always-on services (Uptime Kuma, Prometheus/Grafana, Tailscale, etc. — all floated as options for this node) follow the same pattern: a subdirectory under `infra/infra-node-01/` with its own `docker-compose.yml`, not a Kubernetes manifest.

## Follow-ups

- [x] Bootstrap `infra-node-01` (SSH, hardening, base packages)
- [x] Install Docker
- [ ] Deploy AdGuard Home and complete first-run setup
- [ ] Point router DHCP's DNS server at `192.168.0.82`
- [ ] Add DNS rewrites for existing apps (Open WebUI, ComfyUI) as a first test
- [ ] Decide what runs on this node next (monitoring is the leading candidate, given the recent GPU hang incidents on `gpu-node-01` — see `CLAUDE.md`)
