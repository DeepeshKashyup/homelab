# ADR 0026: EdgeNest Agent and Tool Gateway Run in the Homelab; Cloud Run Is a Stateless Relay

**Status:** Proposed
**Date:** 2026-10-06
**Related to:** [EdgeNest PRD](../product/edgenest-prd.md) §8 / §33 D2 (needed before Phase 0), [ADR 0027](0027-edgenest-private-link-cloudflare-tunnel-access.md) (how the relay reaches the agent), [ADR 0022](0022-homelab-ops-agent-plan.md) (Ops Agent — delivered as this agent's homelab layer), [ADR 0015](0015-cloudnativepg-single-instance-clusterip.md) / [ADR 0017](0017-prometheus-grafana-gpu-monitoring.md) (Postgres and monitoring it builds on)

## Context

EdgeNest's phone app talks to one API. PRD v1.0 put the whole brain behind that API in GCP Cloud Run: authentication, routing, agent runtime, tool policy, sessions, telemetry. Review found three problems with that:

1. **Blast radius.** A Cloud Run service holding cluster tool credentials means a compromise of the public-facing service is a compromise of the cluster tools.
2. **Data locality.** The agent's inputs are homelab data: pod logs, events, metrics, RAG chunks from this repo. With the agent in GCP, all of it leaves the homelab for every request, against PRD principle P2.
3. **No state store.** Cloud Run is stateless, and v1.0 explicitly ruled out Cloud SQL/Redis, yet asked the gateway to own sessions and per-request telemetry.

Separately, every tool call would cross the internet and back, and v1.0 had no plan for how a cloud-hosted agent would safely hold a kubeconfig.

## Decision

Split the EdgeNest API into two services:

**EdgeNest Relay — GCP Cloud Run (stateless):**
- validates device tokens, rate limits, revokes devices
- forwards requests to the Agent and streams responses back
- logs request metadata only (request_id, device_id, timestamps, status, latency), never message content
- holds exactly one homelab credential: the Cloudflare Access service token (ADR 0027)

**EdgeNest Agent — homelab k3s, pinned to `control-plane-01`:**
- remote-tier routing (homelab vs. cloud LLM), agent loop, Tool Gateway (policy, confirmation, audit)
- sessions, memory, audit log, telemetry, job queue → the existing CNPG Postgres cluster (own `Database`/`DatabaseRole`, same pattern as n8n/Open WebUI/Grafana)
- calls Mac Mini Ollama (ADR 0025), k3s API via a dedicated read-only ServiceAccount, Prometheus, ComfyUI
- holds the cloud LLM API key (k8s Secret), so cloud calls are policy-checked in one place
- manifests in `infra/k8s/base/edgenest/`, code in `edge-ai/agent/`

## Alternatives considered

| Option | Why not |
|---|---|
| **Everything in Cloud Run (PRD v1.0)** | The three problems above. |
| **Agent on the Mac Mini** | Mac Mini is outside k3s (ADR 0024), so no ServiceAccount/RBAC for cluster tools and no in-cluster DNS to Postgres/Prometheus; mixes app hosting into the dedicated inference box; it becomes a single point of failure for *both* inference and the agent. |
| **Agent on `infra-node-01`** | Kept outside k3s deliberately so its services survive cluster outages (ADR 0013). The EdgeNest Agent's job is *operating the cluster*, so it gains nothing from that independence. 8GB RAM is also already shared with AdGuard/Vikunja/Uptime Kuma. |
| **No cloud at all (phone on Tailscale → homelab Agent directly)** | Viable and cheaper. Rejected for now because the relay provides a stable public HTTPS endpoint with no VPN client on the phone and an isolation layer where device auth/rate limiting happen before anything reaches the homelab. It also has portfolio value. Because the Relay is deliberately thin, swapping to this later doesn't touch the Agent (PRD §22). |

## Rationale

- **`control-plane-01` has the headroom:** measured ~9% CPU / 18% memory (ADR 0024 context). Postgres, Prometheus, and Grafana already live there, so the Agent's dependencies are local.
- **Blast radius is minimized:** a compromised Relay can only send authenticated chat requests to the Agent, the same thing the phone can do. Tool policy, confirmations, and audit sit behind it, on hardware Deepesh controls.
- **Reuses existing building blocks** instead of adding cloud state services: CNPG Postgres for state, Prometheus/Grafana for observability, cloudflared for ingress.
- **Keeps the cloud bill near zero:** a stateless, scale-to-zero relay with metadata-only logging fits the PRD's <$5/month target.

## Consequences

- **EdgeNest's remote features depend on the homelab being up.** If the homelab is down, the Relay returns "homelab unavailable" and the phone falls back to on-device (Local) answers and the offline question queue. Accepted: the product's purpose is the homelab.
- **The Agent is a new always-on workload on `control-plane-01`**, pinned via `nodeSelector` like Open WebUI.
- **Two deployables instead of one** (Relay + Agent), with a contract between them (PRD §26 API, streamed). The Relay should stay boring: no business logic creeping in.
- **Cloud Run cold starts** add latency to the first request after idle; accepted for MVP (PRD §23).
- **RBAC becomes part of the security design:** the read-only ServiceAccount is created in Phase 1; the write ServiceAccount only in Phase 6, separately.
- **ADR 0022's Ops Agent is delivered as this Agent's homelab layer.** ADR 0022 should be updated to say so.

## Follow-ups

- [ ] Phase 0: Agent stub Deployment + Service in `infra/k8s/base/edgenest/`, pinned to `control-plane-01`, forwarding to Mac Mini Ollama.
- [ ] Phase 0: Relay on Cloud Run with device-token check and streaming passthrough.
- [ ] Phase 1: `edgenest` `Database`/`DatabaseRole` on CNPG; read-only ServiceAccount + ClusterRole (get/list/watch nodes, pods, deployments, events, pods/log).
- [ ] Update ADR 0022 status/text to point here.
