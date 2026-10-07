# ADR 0027: EdgeNest Cloud → Homelab Link via Cloudflare Tunnel + Access Service Token

**Status:** Proposed
**Date:** 2026-10-06
**Related to:** [EdgeNest PRD](../product/edgenest-prd.md) §16 / §22 / §33 D3 (needed before Phase 0), [ADR 0026](0026-edgenest-agent-runs-in-homelab.md) (the Relay/Agent split this connects), [ADR 0019](0019-telegram-bot-webhook-cloudflare-tunnel.md) (the existing named tunnel this extends), [ADR 0012](0012-comfyui-public-tunnel-security-incident.md) (the tunnel anti-pattern this must not repeat)

## Context

Per ADR 0026, the EdgeNest Relay runs in GCP Cloud Run and the EdgeNest Agent runs in k3s on `control-plane-01`. The Relay needs an authenticated, private path to the Agent, under these constraints from the PRD:

- **P4:** no homelab port opened to the public Internet; no router port-forwards for this.
- **Cost:** gateway infrastructure under ~$5/month.
- Only the Agent's API may be reachable through this path, not Ollama, the k8s API, SSH, ComfyUI, Prometheus, or Postgres.
- Must carry streamed chat responses and, from PRD Phase 3, job uploads/result downloads (images, short videos).

The homelab already runs a **named Cloudflare Tunnel** (ADR 0019): a `cloudflared` Deployment on `control-plane-01` (`infra/k8s/base/cloudflared/`), outbound-only, under Deepesh's own Cloudflare account and `deepeshkumar.dev`, currently routing one hostname: `n8n-webhook.deepeshkumar.dev` → n8n.

## Decision

1. **Add a second hostname to the existing tunnel:** `edgenest-api.deepeshkumar.dev` → `http://edgenest-agent.edgenest.svc.cluster.local:<port>`, inserted above the catch-all `http_status:404` rule in `infra/k8s/base/cloudflared/01-configmap.yaml`. Nothing else is added to the tunnel.
2. **Protect that hostname with Cloudflare Access** using a **Service Auth policy** that admits only a dedicated **service token** issued to the Relay. Requests without a valid token are rejected at Cloudflare's edge and never reach the homelab.
3. **The Relay** stores the token's client ID/secret in **GCP Secret Manager** and sends them as `CF-Access-Client-Id` / `CF-Access-Client-Secret` headers on every request to the Agent.
4. **The Agent verifies the `Cf-Access-Jwt-Assertion` header** (signature against the Cloudflare Access team's public keys, plus audience tag) on every request. This is defense in depth: it protects the Agent if the tunnel route were ever misconfigured, or if traffic arrived some other way.
5. **LAN access** to the Agent (development, debugging) stays possible in-cluster/LAN without the Access JWT, but is never exposed through the tunnel.

## Alternatives considered

| Option | Why not |
|---|---|
| **GCP Cloud VPN / HA VPN to the home router** | Per-tunnel hourly pricing alone exceeds the whole $5/month target, and it needs an on-prem VPN endpoint reachable from the internet (inbound port-forward on the home router, against P4). |
| **WireGuard from Cloud Run to a homelab endpoint** | Needs an inbound UDP port-forward at home (against P4) and Cloud Run has no kernel WireGuard; userspace only. |
| **Tailscale (userspace mode) inside the Cloud Run container** | Workable and P4-compliant (outbound only). Kept as the **fallback**: adds a sidecar/userspace proxy to every cold start, a third-party control plane, and ephemeral-node churn on scale-to-zero, for no gain over an already-running tunnel. |
| **Public endpoint with mTLS via router port-forward** | Opens an inbound port; against P4. |
| **Reuse `n8n-webhook` hostname/route** | That hostname is deliberately *not* behind Access, because Telegram's webhook can't present credentials. Mixing EdgeNest into it would either weaken EdgeNest's auth or break Telegram. Separate hostname, separate policy. |

## Rationale

- **Zero new infrastructure and no new inbound exposure:** `cloudflared` already maintains outbound connections from the cluster. Adding a hostname is a ConfigMap edit plus a DNS route.
- **Authentication happens before the homelab sees a packet:** Access rejects unauthenticated requests at Cloudflare's edge, so scanning or abuse never reaches `control-plane-01`.
- **Cost:** Cloudflare Tunnel and Access service tokens are within Cloudflare's free tier for this single-user scale (verify current Zero Trust free-plan limits at setup). Cloud Run → Cloudflare is plain outbound HTTPS, with no VPC connector needed.
- **Consistent with ADR 0019, and distinct from ADR 0012:** a named tunnel under Deepesh's account, one hostname mapped to one Service, with an auth policy on top. That's the opposite of ADR 0012's auto-generated public tunnel with a default password.

## Consequences

- **Cloudflare becomes a dependency of EdgeNest's remote path**, and already is for the Telegram bot. If Cloudflare or the `cloudflared` pod is down, the phone degrades to Local/offline mode.
- **The `cloudflared` Deployment now carries two independent services.** A bad ConfigMap edit can break both, so validate with `cloudflared tunnel ingress validate` before applying, and keep the catch-all 404 last.
- **Size and time limits apply to the proxied path.** Cloudflare caps request bodies on the free plan (100MB at time of writing), and long-held connections can be cut. This is why PRD Phase 3 uses async jobs, capped uploads, and separate short-lived download requests rather than holding a connection for the duration of a video job.
- **Service token rotation** is a manual operation: issue a new token, update Secret Manager, redeploy the Relay, revoke the old one. Set a token expiry and track rotation in Vikunja.
- **TLS:** the phone → Relay leg uses Cloud Run's managed TLS. The Relay → Cloudflare leg uses Cloudflare's edge certificate. Cloudflare → cloudflared is the tunnel's own encrypted connection. cloudflared → Agent is plain HTTP inside the cluster, same as the n8n route.

## Follow-ups

- [ ] Phase 0: create Access application for `edgenest-api.deepeshkumar.dev` with a Service Auth policy + service token (with expiry).
- [ ] Phase 0: add the ingress rule + DNS route; `cloudflared tunnel ingress validate`; confirm `n8n-webhook` still works.
- [ ] Phase 0: Relay sends Access headers from Secret Manager; Agent validates `Cf-Access-Jwt-Assertion` (JWKS + audience).
- [ ] Phase 0 success checks: no token → rejected at Cloudflare; valid token → Agent responds; `11434`/`6443`/`22` unreachable from the internet.
- [ ] Update `infra/k8s/base/cloudflared/README.md` to describe both routes and their different auth postures.
- [ ] Vikunja: service token rotation reminder.
