# ADR 0015: CloudNativePG, Single Instance, ClusterIP-Only, Weekly Logical Backup

**Status:** Accepted
**Date:** 2026-08-23
**Related to:** [ADR 0006](0006-spark-on-kubernetes-followup.md) (same "start small, add complexity when justified" pattern), [ADR 0009](0009-nodeport-then-traefik-ingress.md) (the NodePort-everywhere default this deviates from)

## Context

Several apps on the roadmap (n8n, the `nlp-to-sql` agent, and whatever comes after) need a real relational database, and CLAUDE.md already names CloudNativePG as part of the platform's intended stack. Today there's exactly one non-GPU-contending, disk-rich node (`control-plane-01`) to put it on — the same node Open WebUI and Plex are already pinned to.

Three sub-decisions needed making together: which Postgres deployment mechanism, how many instances, and how it's exposed.

## Decision

- Deploy Postgres via the **CloudNativePG operator** (a `Cluster` custom resource), not a plain Deployment+PVC.
- Run **a single instance** (`instances: 1`), pinned to `control-plane-01` via `nodeSelector`.
- Expose it as **`ClusterIP` only** (no NodePort) — apps reach it in-cluster via CNPG's auto-created `postgres-rw`/`postgres-ro`/`postgres-r` Services; admin access from the Dell G5 goes through `kubectl port-forward`.
- Mitigate the single instance's lack of redundancy with a **weekly `pg_dumpall` CronJob** writing to an external USB drive mounted on `control-plane-01`, with an 8-week retention window.

## Rationale

**CloudNativePG over a plain Deployment+PVC:** it's already the named tool in CLAUDE.md's stack, and it gives declarative per-app database/role management (the `Database`/`DatabaseRole` CRDs) as more apps land on this instance, plus a real path to HA and native physical backups later — without a re-platforming migration when that need shows up. The operator itself is a one-time cluster-wide install; the day-to-day object this repo manages is just the `Cluster` CR, not meaningfully more complex than a Deployment+PVC to read.

**Single instance, not HA:** CNPG's HA model needs multiple instances on separate nodes. Today there's only one node (`control-plane-01`) with spare, non-GPU capacity — `gpu-node-01` is reserved for GPU workloads and already single-purposed between Ollama/ComfyUI. Configuring `instances: 3` today would just fail to schedule or (worse) stack replicas on the same physical disk, which isn't real redundancy. Same "start small" reasoning as ADR 0006's Spark deferral: prove the single-instance baseline first, revisit if/when a second general-purpose node joins the cluster.

**ClusterIP-only, not NodePort:** every other app in this repo follows ADR 0009's NodePort-by-default pattern. Postgres is different in kind, not just another app to expose on the LAN — a database's whole attack surface is "give me credentials, get data," and NodePort would put that directly on the home LAN with no additional network boundary. Nothing today needs Postgres reachable from outside the cluster; every real consumer (agents, n8n) runs as pods that already have in-cluster network access via the Service DNS name. `kubectl port-forward` covers the occasional admin/debugging need from the Dell G5 without a standing exposed port.

**Weekly logical backup to external USB, not CNPG-native physical backup yet:** CNPG's native backup path (`barman-cloud`) targets S3-compatible object storage, which this platform doesn't have yet (no MinIO or equivalent). Building that out just to get backups working today would be solving a bigger problem than the one in front of us. A `pg_dumpall` CronJob to a plain mounted filesystem is well-understood, needs no new services, and directly answers the actual risk: `local-path` storage on `control-plane-01` is plain node-local disk with zero redundancy, so a node wipe or disk failure is otherwise unrecoverable data loss.

## Consequences

- New apps needing a database get a `Database` CR against this one `Cluster`, not their own standalone Postgres — see `infra/k8s/base/postgres/README.md`.
- The external USB drive on `control-plane-01` becomes a piece of infrastructure this platform now depends on for durability — it needs to stay attached and mounted, and its capacity needs occasional checking (8-week retention keeps this bounded, not unbounded).
- Restoring from a `pg_dumpall` backup is a full-instance restore (all databases + roles together), not a granular per-database or point-in-time restore. Acceptable for a homelab-scale disaster-recovery case; not a substitute for real PITR if that's ever needed.
- `enableSuperuserAccess: true` is set on the Cluster (off by default in recent CNPG) so the backup CronJob can run `pg_dumpall`. The superuser secret is only ever read by that one CronJob inside the cluster.
- If/when a second general-purpose node joins the cluster, revisit `instances: 1` for real HA — this ADR's single-instance choice is a today-constraint, not a permanent architectural stance.

## Follow-ups

- [ ] Stand up a real CNPG-native physical backup (`barman-cloud`) with point-in-time recovery once an S3-compatible target exists (e.g. a future MinIO instance) — tracked in Vikunja.
- [ ] Revisit `instances: 1` -> HA once a second non-GPU node exists.
- [ ] Add `Database`/`DatabaseRole` CRs for the first real consumer (n8n or `nlp-to-sql`) once that work starts.
