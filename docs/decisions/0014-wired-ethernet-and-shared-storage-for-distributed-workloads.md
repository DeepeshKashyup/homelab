# ADR 0014: Wired Ethernet for All Compute Nodes, and Network-Shared Storage Before Distributed Workloads

**Status:** Accepted
**Date:** 2026-08-22
**Related to:** [ADR 0006](0006-spark-on-kubernetes-followup.md) (this ADR is a prerequisite for the storage/networking questions that one deferred to "when a real need emerges"), [ADR 0013](0013-infra-node-dedicated-services-adguard-dns.md) (why `infra-node-01` is exempt — see below)

## Context

Deploying Plex on `control-plane-01` (2026-08-22) surfaced a chain of real networking problems while moving two large Blu-ray remux files (~17GB and ~64GB) onto the cluster:

- `control-plane-01` was Wi-Fi-only and capped bulk transfers around ~3.6MB/s, from two compounding causes: the sending machine had two VPN clients silently routing LAN traffic through their tunnels, and — separately, and not fixable in software — `control-plane-01`'s USB Wi-Fi adapter turned out to be **2.4GHz-only hardware**, hard-capping it around ~70Mbit/s regardless of configuration.
- Even after wiring `control-plane-01` via Ethernet, getting the file from a Windows machine onto the right node, then into the right pod, took a multi-step manual dance (transfer to node home directory, then `kubectl cp` into the pod, because a `local-path` PVC's actual host directory isn't predictable ahead of time) — and even the wired transfer hit an SSH-layer connection reset on the larger file, needing a resumable-transfer workaround (`sftp reput` in a retry loop).
- `infra-node-01` separately had its own Wi-Fi networking friction this same day (a router DHCP reservation that wouldn't reliably follow a MAC change, worked around with a netplan-level static address instead) — a different problem, but the same underlying theme: Wi-Fi on these nodes has repeatedly been a source of avoidable trouble.

None of this was fatal for today's workloads (Ollama/Open WebUI/ComfyUI are latency- and bandwidth-modest; Plex mostly serves LAN clients that Direct Play). But `docs/decisions/0006` already flagged that a future Spark-on-Kubernetes (or general distributed ML) decision would need to cover "additional storage and orchestration components" and "how data locality and job scheduling should be handled." Distributed data processing and multi-node ML training are **far** more sensitive to exactly the two things that broke today:

- **Network bandwidth and latency between nodes.** Spark shuffle stages and distributed training gradient/parameter sync move much more data, much more constantly, between nodes than a one-off file copy — a Wi-Fi-capped node wouldn't just be slow to set up, it would silently bottleneck or destabilize every job that touches it.
- **Where data actually lives.** Today's `local-path` PVCs pin data to whichever specific node a pod happens to be scheduled on — fine for single-node workloads (Ollama's models, ComfyUI's outputs, Plex's media), but incompatible with distributed compute, where multiple nodes need concurrent access to the same dataset without manually copying it around each time (exactly the friction just hit with one movie file — magnified across every dataset a future Spark job or training run would touch).

## Decision

1. **Every node that runs cluster compute workloads must be on wired Ethernet, not Wi-Fi**, as a baseline requirement going forward — not just a nice-to-have. This applies to `control-plane-01` and `gpu-node-01` today, and to any future compute node added to the cluster.
2. **Plan for network-shared storage reachable by all cluster nodes** (e.g. NFS from a dedicated box, or a small NAS) as a prerequisite to be in place *before* starting distributed data processing (Spark) or multi-node ML training work — not before general single-node workloads, which the current `local-path` pattern continues to serve fine.

`infra-node-01` is explicitly **exempt** from the wired-Ethernet requirement: per ADR 0013 it deliberately stays outside the k3s cluster and only runs light, latency-insensitive infra services (DNS today), so it never participates in the kind of node-to-node traffic this ADR is about.

## Rationale

- **Evidence, not speculation.** This isn't a hypothetical concern — `control-plane-01`'s Wi-Fi hardware ceiling and the VPN LAN-routing issue were both real, both diagnosed today, and both would have been far more disruptive (and far harder to diagnose mid-job) if hit during an actual Spark shuffle or a multi-node training run instead of a one-off file copy.
- **Matches the project's incremental philosophy (ADR 0004, ADR 0006).** This isn't "buy a NAS now because Plex needs it" — Plex's own storage need is already met by `control-plane-01`'s local disk. It's a deliberate, sequenced prerequisite: get wired networking right while the stakes are low (LLM serving, media), so it's already solved by the time Spark/distributed ML actually shows up, rather than discovering it mid-migration the way today's Plex work discovered it mid-file-transfer.
- **Avoids a repeat purchase mistake.** `control-plane-01`'s Wi-Fi adapter limitation was only discovered after the fact. Any future compute node purchase should default to wired Ethernet from day one and verify it, rather than assuming Wi-Fi is "good enough" until a workload proves otherwise.

## Consequences

- `control-plane-01`'s wired `eno1` (`192.168.0.47`, currently a secondary/manual-use DHCP address — see `CLAUDE.md`) should be promoted to its stable, primary identity rather than staying a manual fast-path workaround. That's a bigger, more careful change (this node is the k3s control plane; `.106` is what the cluster, `gpu-node-01`, and the SSH alias currently know it as) — tracked as a follow-up, not done by this ADR.
- Shared storage is **not** being added now. Current per-node `local-path` PVCs (Ollama models, ComfyUI models/output, Plex config/media) remain the right pattern for workloads deliberately pinned to one node — nothing about this ADR changes them.
- This becomes a checklist item for the eventual dedicated Spark-on-Kubernetes ADR that ADR 0006 deferred: that ADR can now assume wired networking and shared storage are prerequisites to satisfy first, rather than open questions to design from scratch at that point.
- Any future hardware expansion phase for shared storage should be evaluated against the same used-hardware and "match current-phase needs" criteria already applied to compute nodes (ADR 0001, ADR 0002) — not over-bought ahead of an actual Spark/ML workload driving it.

## Follow-ups

- [ ] Promote `control-plane-01`'s wired `eno1` (`.47`) to its stable/primary address, replacing Wi-Fi as primary (router DHCP reservation or static netplan config, plus updating the SSH alias, kubeconfig references, and anything else that currently assumes `.106`)
- [ ] Verify `gpu-node-01` has no equivalent Wi-Fi fallback path relied on anywhere (it's already wired — confirm nothing silently depends on its Wi-Fi interface)
- [ ] When a compute node is purchased or repurposed in the future, verify wired Ethernet capability (and actually wire it) as part of bootstrap, not as an afterthought
- [ ] Revisit shared storage options (NFS export from an existing node vs. a small dedicated NAS box) once Spark-on-Kubernetes work is actually scheduled, per ADR 0006's deferred future decision
- [ ] Fold this ADR's prerequisites into that future Spark-on-Kubernetes ADR when it's written
