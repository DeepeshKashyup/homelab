# ADR 0017: Prometheus + Grafana for Cluster and GPU Metrics

**Status:** Accepted (in progress — Helm chart not yet deployed as of this writing)
**Date:** 2026-08-25
**Related to:** [ADR 0008](0008-nvidia-device-plugin-default-runtime.md) (the device plugin whose single-GPU resource this ADR deliberately avoids contending with), backlog #8 (cluster audit that fed this), backlog #12 (GPU hang root-cause investigation this exists to support)

## Context

`gpu-node-01` has had one confirmed hard-crash incident (Aug 19/20 — see the audit notes folded into CLAUDE.md's "Cluster audit performed" entry) with two suspected causes competing: a possibly-undersized PSU (~500W suspected, unconfirmed — RTX 5060 Ti alone can draw up to 180W under load, plus the rest of the system), and/or a second-hand card needing thermal paste reapplication (degraded cooling → thermal throttling or shutdown under sustained load). Both hypotheses need the same thing to test: **metrics over time**, not a point-in-time reading.

What already existed wasn't enough to tell these apart:
- `infra/gpu-node-01/gpu-temp-exporter/` (Uptime Kuma + a stdlib JSON endpoint) gives pass/fail alerting on temperature at 5-minute intervals — no history, no VRAM, no power draw, and its own README explicitly deferred this exact need ("If you want real graphs, that's a Prometheus + exporter + Grafana stack — a bigger addition, deliberately not what this is").
- `metrics-server` (bundled with k3s) only feeds `kubectl top` and HPA — it doesn't store history either, and knows nothing about GPU-specific metrics at all.

The plan going forward: get temperature/VRAM/power graphing live, then run a small ComfyUI video-generation test while watching the graphs, to see whether a specific metric (power spike, thermal ramp) correlates with instability before it escalates to a hang.

## Decision

- Deploy **`prometheus-community/kube-prometheus-stack`** (the standard Helm bundle: Prometheus + Grafana + Alertmanager + `node-exporter` + `kube-state-metrics`) into a new `monitoring` namespace — `infra/k8s/base/monitoring/`.
- Pin Prometheus, Grafana, Alertmanager, and the operator to **`control-plane-01`** via `nodeSelector` (`node-exporter` stays a DaemonSet on both nodes, since host-level CPU/mem/disk from *each* node is the point).
- Run the GPU-specific exporter (`utkuozdemir/nvidia_gpu_exporter`) as a **systemd service directly on `gpu-node-01`** — `infra/gpu-node-01/nvidia-gpu-exporter/` — not as a Kubernetes workload, scraped by Prometheus as a static target (`192.168.0.79:9835`).
- Expose Grafana via **NodePort `30300`**, matching the existing pattern (ADR 0009). Prometheus/Alertmanager stay internal-only (`kubectl port-forward` if ever needed).
- Grafana's admin password is **not committed to the repo** — the chart auto-generates one into a Secret, retrieved with `kubectl get secret prometheus-grafana -n monitoring -o jsonpath=... | base64 -d`.

## Rationale

**Why a Helm chart instead of hand-written manifests.** This is the first time this repo installs anything via Helm rather than plain `kubectl apply -f`. The tradeoff: a chart pulls in more moving parts than you write yourself (worth understanding what you're getting), but `kube-prometheus-stack` specifically is the de-facto standard bundle for exactly this combination — a Prometheus Operator that manages Prometheus/Alertmanager via CRDs, wired to Grafana and `node-exporter`/`kube-state-metrics` out of the box, with sane defaults and years of community hardening. Hand-rolling the operator's RBAC, CRDs, and the Prometheus↔Grafana↔datasource wiring from scratch would be re-deriving a solved problem for no real benefit — and this repo's existing apps (Ollama, ComfyUI, Plex, Postgres-via-operator) are already comfortable depending on well-known upstream images/operators rather than reinventing them.

**Why the GPU exporter runs on the host (systemd), not in Kubernetes — the one non-obvious call here.** Every other exporter/service the platform runs (Ollama, ComfyUI, `node-exporter`) is a normal pod. The GPU exporter is the exception, and the reason is specific to how the NVIDIA device plugin works (ADR 0008): it advertises the GPU to Kubernetes as an *extended resource*, `nvidia.com/gpu`, with a fixed quantity — on this node, **1** (one physical card). Any pod that requests `nvidia.com/gpu: 1` in its spec claims that entire unit for as long as it runs; a second pod requesting the same resource simply can't schedule until the first releases it, regardless of whether the first pod is actually *using* the GPU at that instant. That's the same mechanism ComfyUI and Ollama already share the card through today — manually toggling one deployment's `replicas` to `0` before scaling the other's to `1` (see CLAUDE.md).

If the GPU exporter ran as a normal pod requesting that resource, it would need to hold the GPU *permanently* (metrics collection is a long-running service, not a one-shot job) — which would mean neither Ollama nor ComfyUI could ever schedule again. But `nvidia-smi` (what the exporter shells out to) doesn't actually need exclusive compute access to read temperature/power/memory stats — it just talks to the NVIDIA driver via NVML, the same way `nvidia-smi` works fine on a normal desktop OS with no notion of "reserving" the GPU for one process. The device-plugin's exclusivity is a Kubernetes scheduling abstraction, not a hardware constraint — so running the exporter *outside* that abstraction (as a plain host process with the `nvidia-smi` binary on `$PATH`, same approach as `gpu-temp-exporter`) sidesteps the contention entirely. Prometheus can still reach it fine as a static scrape target — a service doesn't have to be *in* the cluster to be *monitored by* the cluster.

**Why node-pin Prometheus/Grafana to `control-plane-01`.** Same reasoning already applied to Open WebUI (ADR-adjacent, CLAUDE.md) and Postgres (ADR 0015): `gpu-node-01` is deliberately kept as uncontended as possible for GPU/inference work, and nothing about a metrics stack needs to run on the GPU box. `control-plane-01` has spare CPU/RAM and is where every other non-GPU service already lives.

**Why NodePort for Grafana, not something else.** Consistent with ADR 0009's stated default (NodePort until Traefik Ingress is worth the migration cost) — no reason to special-case this one app when the same tradeoffs apply.

**Why the Grafana password isn't in git.** This repo is public on GitHub. A committed plaintext admin password for a service that's reachable on the LAN (and, per the ADR 0009 exposure pattern, effectively at whatever the router's port-forward maps to) is a real credential leak, not a homelab-scale risk to shrug off. Letting the chart auto-generate one into a Kubernetes Secret and retrieving it out-of-band costs nothing.

## Consequences

- This is the first Helm-managed component in the cluster — `helm list -n monitoring` / `helm upgrade` is now a maintenance path that didn't exist before, alongside the existing plain-manifest apps.
- `gpu-node-01` now has **two** independent host-level (non-k8s) services: `gpu-temp-exporter` (JSON, Uptime Kuma, alerting) and `nvidia_gpu_exporter` (Prometheus text format, Grafana, graphing). They serve genuinely different jobs (alert vs. graph) rather than being redundant, but it's two things to remember exist outside `kubectl get pods`.
- Prometheus's 20Gi PVC and Grafana's 2Gi PVC are both `local-path` (node-local, `control-plane-01`) — same lack-of-redundancy caveat as every other `local-path` volume in this cluster (see ADR 0015's Postgres backup discussion for the general shape of this risk). Metrics history is not currently backed up; acceptable since it's observability data, not a system of record.
- Anyone extending this stack (e.g. adding a `ServiceMonitor` for a new pod-based exporter) gets the CRD-driven pattern kube-prometheus-stack sets up for free; anyone adding a *host-level* exporter (a third node, a new non-k8s service) should follow the same static-scrape-target pattern as the GPU exporter rather than trying to force it into a `ServiceMonitor`.

## Follow-ups

- [ ] Confirm `gpu-node-01`'s actual PSU wattage (physical check) — the ~500W suspicion driving this ADR is still unconfirmed.
- [x] Run a small ComfyUI video-generation test while watching Prometheus, looking for a power/thermal signature correlated with instability — done 2026-08-25, see "Staged stress-test results" below. Stage A was clean.
- [ ] Consider physically reseating/repasting the GPU if thermal data (once graphed) shows it running hotter than expected at the observed load — no evidence of this yet at light load (Stage A); revisit once heavier stages run.
- [ ] If a third non-GPU node ever joins, revisit whether Prometheus/Grafana should stay pinned to `control-plane-01` specifically, or just "any non-GPU node."

## Staged stress-test results

The plan is to work up to the original incident's actual conditions (dual 14B Wan2.2 I2V, both `high_noise`/`low_noise` checkpoints loaded together) in stages, watching Prometheus at each step, rather than jumping straight back to the workload that caused the crash.

**Stage A — Wan2.1 T2V, 1.3B params, single model** (2026-08-25): 832×480, 33 frames, 30 steps, `wan2.1_t2v_1.3B_fp16.safetensors`.

| Metric | Idle | Peak | Recovery |
|---|---|---|---|
| Temperature | 36°C | **74°C** | 40°C within ~2 min |
| Power draw | ~10.7W | **160W** (89% of 180W cap) | ~11W within ~2 min |
| VRAM | ~149MB | ~9.5GB resident | stays loaded until next model swap |

Clean run, no throttling, no Xid errors, `Prompt executed in 117.25 seconds`, all 30/30 sampler steps completed. Confirms the monitoring pipeline captures real signal and that a light single-model workload is nowhere near the danger zone on this card.

- [ ] Stage B — Wan2.2 I2V, dual 14B (`high_noise` + `low_noise`) via the already-downloaded `lightx2v_4steps` LoRAs (fast/light 4-step path), small resolution/length.
- [ ] Stage C — Wan2.2 I2V, dual 14B, fuller settings approaching the original incident's conditions (resolution/length/step count not yet known — the incident predates this monitoring stack).
