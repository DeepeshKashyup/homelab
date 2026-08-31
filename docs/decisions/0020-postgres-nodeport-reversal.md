# ADR 0020: Reverse ADR 0015 — Expose Postgres via NodePort for Direct DB-Client Access

**Status:** Accepted
**Date:** 2026-08-31
**Related to:** [ADR 0015](0015-cloudnativepg-single-instance-clusterip.md) (the decision this reverses), [ADR 0009](0009-nodeport-then-traefik-ingress.md) (the NodePort-everywhere pattern this now brings Postgres in line with)

## Context

ADR 0015 deliberately kept Postgres `ClusterIP`-only, reasoning that *"a database's whole attack surface is 'give me credentials, get data,' and NodePort would put that directly on the home LAN with no additional network boundary"* — `kubectl port-forward` was the intended path for the "occasional admin/debugging need."

In practice, once real GUI DB-client usage started (TablePlus, browsing `app`/`n8n`/`openwebui`/`grafana`), the `ssh -L ... | kubectl port-forward` tunnel from the jump box turned out to be a real, recurring friction point — it only lives as long as a foreground process/session does, dies on disconnect, sleep/wake, or a Claude Code session ending, and has to be manually re-established every time. A persistent tunnel (`autossh` + a `launchd` service) was offered as a zero-new-exposure fix for exactly this friction, but the decision made here is to accept the NodePort exposure instead, for simplicity of not maintaining a separate always-on tunnel process at all.

## Decision

Add a NodePort Service for Postgres's `-rw` endpoint, reusing CNPG's own pod selector (`cnpg.io/cluster: postgres`, `cnpg.io/instanceRole: primary`) rather than editing CNPG's own managed `postgres-rw` Service directly — that Service is actively reconciled by the operator, and hand-editing its `type` would likely get reverted on the next reconcile. A separate, repo-owned Service avoids fighting the operator for control of the same object.

## Rationale

**Why a new Service instead of editing `postgres-rw` or using CNPG's `managed.services` override:** keeps the change entirely on this repo's side (a plain manifest, same pattern as every other app's Service here) rather than depending on CNPG-version-specific `Cluster.spec.managed.services` override behavior, which risks the same fragility already flagged for the LangChain node schemas in `infra/k8s/base/n8n/`.

**Accepting the risk ADR 0015 called out:** the LAN-exposure risk described there is real and unchanged by this ADR — anything on the home LAN with valid credentials can now reach Postgres directly, with no additional network boundary beyond the credential check itself. This is accepted as a conscious tradeoff for eliminating the tunnel-maintenance friction, not a disagreement that the risk exists. Every database's password remains a CNPG-generated Secret, never a literal in a committed manifest (same practice as every other credential in this repo) — that mitigation is unaffected by this change.

**Why not the persistent-tunnel alternative:** it was offered specifically as a way to get "always available" access *without* new exposure, and was explicitly not the direction chosen here — recorded so a future reader doesn't wonder whether it was considered.

## Consequences

- Postgres is now reachable from anywhere on the home LAN at `<any-node-ip>:30432`, not just from in-cluster pods or through a `kubectl port-forward` tunnel.
- `kubectl port-forward` still works as before and needs no credential exposed on the network beyond SSH — worth preferring it again if this platform's threat model ever changes (e.g., untrusted devices join the home LAN).
- If a second general-purpose node ever joins the cluster and ADR 0015's `instances: 1` → HA follow-up happens, this NodePort continues to work unchanged (NodePort Services route to the right pod via the same `cnpg.io/instanceRole: primary` selector regardless of which node is currently primary).
- Should ADR 0015's other deferred follow-up (CNPG-native `barman-cloud` physical backup via a future MinIO/S3-compatible target) land, that's unrelated to this change — this ADR only concerns network exposure, not backup strategy.

## Follow-ups

- [x] Add `infra/k8s/base/postgres/03-nodeport-service.yaml`, NodePort `30432`.
- [ ] Consider narrowing exposure later (e.g. a `NetworkPolicy` restricting which source IPs can reach the NodePort) if the home LAN's trust model ever changes.
