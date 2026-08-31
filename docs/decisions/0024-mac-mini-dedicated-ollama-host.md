# ADR 0024: Mac Mini as a Dedicated Ollama Host (Not a k3s Node)

**Status:** Proposed
**Date:** 2026-08-31
**Related to:** [ADR 0023](0023-dev-agent-swarm-plan.md) and [ADR 0022](0022-homelab-ops-agent-plan.md) (both assume agent inference routes to `gpu-node-01`'s Ollama — this ADR gives them a second option), [ADR 0015](0015-cloudnativepg-single-instance-clusterip.md) (the Postgres HA follow-up this does NOT solve), backlog #9/#14 (the GPU-tainting and shared-storage items this is adjacent to but distinct from)

## Context

Capacity planning conversation, prompted by the two new agent projects (ADR 0022, 0023): measured data showed `control-plane-01` has abundant headroom (9% CPU, 18% memory used) but `gpu-node-01`'s single GPU is **already fully committed at all times** (`nvidia.com/gpu 1/1`, 100% allocated to whichever of Ollama/ComfyUI is scheduled) — every planned agent workload's actual inference load lands on that same contended resource.

A Mac Mini was proposed as a way to add capacity. The real question was whether one box could solve two different needs at once: relieving GPU contention for agent inference, *and* adding a second general-purpose node for Postgres HA (ADR 0015's explicit deferred follow-up). It cannot cleanly do both — Apple Silicon's unified memory is a genuine strength for LLM inference, but k3s does not run natively on macOS (it needs Linux-specific kernel features), so cluster membership would mean a Linux VM layer, a real complexity cost for a need (Postgres HA) that isn't urgent per the current headroom numbers anyway.

## Decision

Add a Mac Mini as a **dedicated Ollama host, running natively on macOS, outside the k3s cluster entirely** — the same architectural category as `infra-node-01` or the jump boxes, not a cluster node. It exposes Ollama's REST API on the LAN (port 11434, same protocol `gpu-node-01`'s Ollama already speaks), reachable by anything that currently talks to `gpu-node-01`'s Ollama Service.

**Explicitly not attempting** to join it to k3s via a Linux VM — deferred as a separate, later decision if Postgres HA capacity actually becomes needed, not bundled into this one.

## Rationale

**Why native macOS, not a VM/k3s node:** Ollama has first-class Metal/Apple Silicon support — no virtualization layer needed to get GPU-accelerated inference. Forcing k3s onto it via a VM would add real complexity (UTM/Lima/Multipass, a VM boundary between the host GPU and the workload) purely to satisfy cluster membership, for a benefit (general-purpose k3s capacity) this box isn't primarily being added for.

**Why this actually relieves the real bottleneck:** unlike `control-plane-01` (measured abundant headroom), `gpu-node-01`'s GPU is the thing every future agent workload's inference load lands on. A second, independent Ollama host — not sharing that GPU at all — genuinely relieves contention rather than just moving it around. Apple Silicon's unified memory means the Mac Mini's GPU isn't capped by a fixed VRAM pool the way the RTX 5060 Ti's 16GB is, so a well-specced config can comfortably run models at least as large, with real headroom for concurrent agent+interactive use.

**Config guidance — prioritize RAM over everything else.** Unified memory size is the single spec that directly caps usable model size/headroom for this use case; storage needs are modest by comparison (a handful of models at 5–15GB each, well under 200GB total — no reason to pay for a large SSD tier here). Exact current Mac Mini M6 RAM tiers/pricing are outside this ADR's knowledge (verify against Apple's current lineup directly at purchase time) — the guidance is qualitative and durable regardless of the specific SKU available when this is actually bought: get the highest RAM configuration justifiable, not the largest disk.

**How agent workloads should route between two Ollama instances** — not yet decided, a real follow-up: either dedicate this Mac Mini specifically to agent-workload inference (Ops Agent, Dev Swarm) while `gpu-node-01` stays for interactive chat/ComfyUI, or some other split. ADR 0022/0023 should be updated once this box exists and the split is decided.

## Consequences

- Does **not** solve Postgres HA / general-purpose k3s capacity (ADR 0015's follow-up, backlog #14's prerequisite) — that remains open, and the honest path there is still a plain Linux mini-PC later, matching `control-plane-01`/`infra-node-01`'s existing pattern, not this box.
- Two independent Ollama hosts means agent-facing config (n8n workflows, the future Ops Agent, the future Dev Swarm) needs to know which one to call — worth deciding explicitly rather than hardcoding one and forgetting the other exists.
- A new always-on device to account for in the hardware inventory / `docs/hardware/` — should get its own doc there once purchased, matching the pattern for every other node.
- No firewall/exposure decision needed beyond the existing LAN-NodePort-style pattern — Ollama's API has no built-in auth today on `gpu-node-01` either (relies entirely on LAN-only reachability), so this should follow the same posture, not a stricter or looser one, unless a reason to change that surfaces.

## Follow-ups

- [ ] Purchase — confirm current Mac Mini M6 RAM tiers/pricing at time of purchase (not known at ADR-writing time).
- [ ] Install Ollama natively, pull the same/equivalent model set already on `gpu-node-01` (or a different set, if this box is meant to run larger models specifically).
- [ ] Decide and document the actual routing split between the two Ollama hosts for agent workloads.
- [ ] Add `docs/hardware/mac-mini-ollama.md`, matching the existing per-node hardware doc pattern.
- [ ] Consider an AdGuard Home DNS rewrite for it (e.g. `ollama2.homelab.local`), same pattern as other LAN services.
- [ ] Update ADR 0022/0023 once built, to reference which Ollama host their inference actually targets.
