# ADR 0018: GPU Node Crash Root Cause — Unbounded ComfyUI Host Memory, Not GPU/Thermal/PSU

**Status:** Accepted
**Date:** 2026-08-25
**Related to:** [ADR 0017](0017-prometheus-grafana-gpu-monitoring.md) (the monitoring stack that caught this live), backlog #12 (GPU hang root-cause investigation this closes out — with a different answer than expected)

## Context

Backlog #12 set out to root-cause `gpu-node-01`'s recurring hard-hang incidents, working from two hardware hypotheses: an undersized PSU (~500W suspected) and possible thermal-paste degradation on the second-hand GPU. ADR 0017 stood up Prometheus/Grafana specifically to test these by watching temperature/power/VRAM during a staged escalation toward the original incident's workload (dual 14B Wan2.2 I2V).

Stage A (Wan2.1 T2V, 1.3B, single model) ran clean. **Stage B (Wan2.2 I2V, dual 14B, via the 4-step lightning LoRAs) crashed the node** — a real, live recurrence, this time fully instrumented.

## What the GPU metrics showed (and didn't show)

Temperature and power were completely unremarkable the entire time: stable at 76–77°C and ~141–148W (well under the card's 180W cap) for over ten minutes, with no upward trend. The `nvidia_gpu_exporter` scrape simply stopped returning data between one 5-second poll and the next — no gradual ramp, no throttling signature, nothing that looked like a GPU or power-delivery problem building up. `kubectl get nodes` confirmed `NotReady`; SSH was unresponsive; no fan response — the same signature as the original Aug 19/20 incident. Recovered via hard power-off/on per the standing operating rule. Post-boot `journalctl` showed the identical unclean-shutdown fingerprint as before (ext4 journal recovery, orphaned inodes cleared) — this time the FAT boot partition showed the same thing too ("Fs was not properly unmounted").

**In short: the GPU itself was fine. Whatever crashed the node happened somewhere else, and the GPU-focused monitoring in ADR 0017 — while necessary to rule this out — was looking in the wrong place for the actual answer.**

## What actually happened

The user caught it first, by asking why a Grafana Kubernetes-namespace dashboard showed the `comfyui` pod's memory usage climbing toward 22GiB — a metric this investigation hadn't been watching (`container_memory_working_set_bytes`, host RAM via cAdvisor/kubelet, entirely separate from the GPU VRAM `nvidia_gpu_exporter` tracks). Querying Prometheus's stored history for the full window showed the real peak: **`container_memory_working_set_bytes{namespace="comfyui"}` reached ~45–48GB**, in two jumps — first to ~25–27GB when the `high_noise` 14B checkpoint loaded, then to ~45–48GB when `low_noise` loaded alongside it — against `gpu-node-01`'s **30GB RAM + 8GB swap = 38GB total capacity**. Demand exceeded total capacity (RAM+swap) by roughly 10GB.

The `comfyui` Deployment (`infra/k8s/base/comfyui/01-comfyui.yaml`) requests `nvidia.com/gpu: 1` but sets **no CPU or memory `resources` at all**. Nothing in Kubernetes — no container cgroup limit, no kubelet eviction (the node's `HardEvictionThresholds` only cover `imagefs.available`/`nodefs.available`, not `memory.available` — confirmed in the post-recovery kubelet log) — was ever going to stop this pod's host-RAM usage from growing without bound. Two contributing factors made the actual demand this large: ComfyUI's dynamic CPU-offload staging holds full model weights in host RAM as a buffer for VRAM swapping (not just the active layers), and Stage A's smaller model was never evicted from host RAM even though it *was* evicted from VRAM (VRAM eviction and host-RAM eviction are apparently independent in ComfyUI's cache).

No kernel `OOM killer invoked`/`Killed process` message appears in either crash's logs — the system became unresponsive before or without the OOM killer successfully intervening, consistent with a severe memory-pressure/swap-thrashing collapse taking down the whole node (including whatever lets fans respond and SSH answer) rather than a clean, contained kill.

**This also retroactively explains the original Aug 19/20 incident**, which was described as happening during "the heaviest workload yet (dual 14B Wan 2.2 video generation)" — the same workload class, same missing safeguard, almost certainly the same mechanism. The PSU and thermal-paste hypotheses that motivated ADR 0017 are not disproven by this (still worth confirming physically at some point), but they're no longer the leading explanation for *these* crashes — this one has a direct, evidenced, software-fixable cause.

## Decision

- Add explicit `resources.requests.memory` / `resources.limits.memory` to the `comfyui` Deployment, sized to leave real headroom below the node's 30GB physical RAM for the OS, kubelet, containerd, and the cluster's other pods on this node (`nvidia-device-plugin`, `svclb-traefik`, `node-exporter`).
- Apply the same discipline to the `ollama` Deployment on this node for consistency, even though its models are smaller and it hasn't caused this failure mode — the gap (no memory limit at all) is the same, and defense-in-depth here costs nothing.
- Document, explicitly, that **a memory limit changes the failure mode, it does not make the dual-14B workload succeed on this hardware.** A container hitting its cgroup memory limit gets OOM-killed and the pod restarts — contained, visible, recoverable — instead of the whole node locking up. But the actual peak demand observed (~45–48GB) is well above any limit that leaves the node usable for anything else, so the *specific* workflow that crashed Stage B will still fail under a memory limit; it'll just fail safely instead of taking the node down.

## Rationale

**Why a memory limit and not just "don't run that workflow again."** The unbounded-memory gap isn't specific to this one Wan2.2 workflow — it's a property of every workload this Deployment will ever run, since nothing constrains it. The next large model, the next LoRA stack, the next longer/higher-resolution generation could reproduce the same node-wide crash. A memory limit is the general fix; avoiding one specific workflow is not.

**Why this is a Kubernetes-level fix rather than a ComfyUI-level one.** ComfyUI's own dynamic VRAM/offload management is doing something reasonable in isolation (stage weights in host RAM, swap the active portion into VRAM) — the problem is that nothing above it enforces a ceiling. Kubernetes' `resources.limits.memory` is exactly the mechanism designed for this: it doesn't require trusting the application to self-limit, it enforces the boundary at the cgroup level regardless of what the process inside does.

**Why this matters beyond just fixing one crash.** This is a first real example, on this platform, of a single pod with no resource limits taking an entire node down — worth treating as a general lesson (every future GPU-adjacent, memory-hungry workload on this cluster should ship with explicit `resources.limits.memory` from day one) rather than a one-off patch.

## Consequences

- The dual-14B Wan2.2 workflow that crashed Stage B **will not run successfully on `gpu-node-01` as configured** even after this fix — it needs either more system RAM, or a workflow/model change that avoids holding both full 14B checkpoints in host RAM simultaneously (e.g. explicit sequential load/unload between the high-noise and low-noise stages, if the ComfyUI workflow/node ecosystem supports that — not yet investigated). Backlog #12's planned "Stage C" (fuller settings, closer to the original incident) is deferred until one of those is true — running it against a memory-limited pod would just demonstrate the same OOM-kill, not new information.
- Every future GPU-adjacent Deployment on this cluster should set an explicit memory limit from the start, not added retroactively after a crash.
- The PSU/thermal-paste hypotheses stay open as a physical-inspection follow-up (cheap to confirm, no reason not to), but are no longer the leading theory for why this node has hung.
- ADR 0017's monitoring stack proved its worth here even though it didn't catch the mechanism it was built to catch — it gave the timeline precision (exact 5-second crash window) that made correlating against the Grafana namespace-memory panel possible at all.

## Follow-ups

- [ ] Add `resources.requests.memory`/`resources.limits.memory` to `infra/k8s/base/comfyui/01-comfyui.yaml` (proposed: request `8Gi`, limit `24Gi` — leaves ~6GB headroom on the 30GB node for OS/kubelet/other pods; revisit the exact number once real usage patterns are better understood).
- [ ] Add the same to `infra/k8s/base/ollama-openwebui/`'s `ollama` Deployment.
- [ ] Investigate whether the Wan2.2 I2V workflow can sequentially load/unload the high-noise and low-noise 14B checkpoints instead of holding both in host RAM at once — would make the full workload fit even on this node's RAM.
- [ ] Still confirm `gpu-node-01`'s actual PSU wattage physically — unconfirmed either way, cheap to check, no longer urgent.
- [ ] Consider setting a `memory.available` hard eviction threshold in kubelet config (currently only `imagefs`/`nodefs` are configured) as a second, cluster-wide layer of defense against this failure mode, independent of any one Deployment remembering to set limits.
