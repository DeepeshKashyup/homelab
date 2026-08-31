# ADR 0021: Migrate Vikunja from SQLite to the Shared Postgres Cluster

**Status:** Accepted
**Date:** 2026-08-31
**Related to:** [ADR 0013](0013-infra-node-dedicated-services-adguard-dns.md) (the independence-from-the-cluster reasoning this cuts against), [ADR 0020](0020-postgres-nodeport-reversal.md) (the NodePort this migration depends on to even be reachable from `infra-node-01`), [ADR 0015](0015-cloudnativepg-single-instance-clusterip.md) (the shared Postgres cluster itself)

## Context

Vikunja (the homelab backlog/Kanban board) runs via `docker-compose` on `infra-node-01`, deliberately **outside** the k3s cluster — ADR 0013's reasoning was explicitly that it should stay independent of the thing it tracks work for, so it's still usable to record an incident or plan recovery even if the cluster itself is down. It has run on local SQLite since it was stood up.

Separately, this platform has been consolidating app databases onto the shared CloudNativePG Postgres cluster (n8n, Open WebUI, Grafana) for real backup coverage (weekly `pg_dumpall`) instead of unbacked-up per-app SQLite files on local-path PVCs. Vikunja is the natural next candidate by that same reasoning — except it's the one app where the cost of doing so is real and specific, not hypothetical.

## The tradeoff, accepted knowingly

Moving Vikunja's database onto the shared Postgres cluster (which lives *inside* k3s, on `control-plane-01`) makes Vikunja unusable during exactly the scenario ADR 0013 placed it outside the cluster to survive: a `control-plane-01` outage, a k3s issue, or the Postgres pod itself being down. `infra-node-01` and its other services (AdGuard Home, Uptime Kuma) remain independent — only Vikunja's specific value as an always-available incident/recovery tracker is given up here.

This is accepted as a conscious tradeoff, same category of decision as ADR 0020: durable, backed-up, consistent data across every app outweighed the "survives a cluster outage" property for this specific app. Recorded explicitly so a future reader doesn't mistake this for an oversight.

This migration would not even be *possible* without ADR 0020's NodePort — Postgres was `ClusterIP`-only before that, unreachable from `infra-node-01` (outside the cluster) at all.

## Decision

- Migrate Vikunja's backend from SQLite to a dedicated `vikunja` database/role on the shared Postgres cluster (`infra/k8s/base/postgres/04-vikunja-role-db.yaml`), reached over the LAN via the NodePort (`192.168.0.47:30432`) since `infra-node-01` is outside the cluster.
- Unlike the Open WebUI/Grafana Postgres migrations, this is a **real data migration**, not a fresh start — the backlog itself (45 tracked items, done/priority/description state built up over weeks) is not disposable.
- `Database.spec.template: template0`, not the default `template1` — proactively avoiding the "source database template1 is being accessed by other users" lock gotcha hit migrating Open WebUI/Grafana (see `infra/k8s/base/postgres/README.md`'s Gotcha section). `template0` is never used for direct connections in normal operation.
- Migration order: point a fresh Vikunja instance at the new empty Postgres database first and let it run its own internal migrations (creating the exact schema the running Vikunja version expects), *then* load data from the old SQLite file into that already-correctly-shaped schema via `pgloader` (run as a throwaway Docker container, not installed on `infra-node-01`'s host) — rather than trusting a generic tool's schema inference. The original SQLite file is only ever read from, never modified, during this process — a built-in rollback path for free.

## Consequences

- Vikunja becomes dependent on `control-plane-01`, k3s, the Postgres pod, and the LAN NodePort all being reachable — a real new failure mode for what was previously a maximally-independent service.
- Vikunja's data now gets weekly `pg_dumpall` backup coverage (same as every other app on the shared cluster) instead of living only on `infra-node-01`'s local disk with no backup at all.
- If `infra-node-01`'s independence-from-the-cluster property is ever needed again for incident tracking specifically, the honest fallback is a paper/offline note during an outage, or standing up a separate emergency-only tracker — not something this ADR builds, just naming the gap.
- The old SQLite file stays on `infra-node-01` as an archived backup for a retention window after cutover, in case anything is found wrong post-migration.

## Follow-ups

- [ ] Apply `04-vikunja-role-db.yaml`, generate credentials.
- [ ] Point a fresh Vikunja instance at the empty database, confirm its own migrations create the schema.
- [ ] Back up the current `data/db/vikunja.db`, migrate data via `pgloader`.
- [ ] Verify row counts, spot-check known items (e.g. backlog #16/#17/#18/#40's `done` state and descriptions), confirm login still works.
- [ ] Cut over `docker-compose.yml` to the Postgres config; update `infra/infra-node-01/vikunja/README.md`.
- [ ] Keep the old SQLite file archived, not deleted, for a defined retention window.
