# ADR 0025: Consolidate Ollama onto the Mac Mini; Dedicate the RTX to ComfyUI

**Status:** Proposed
**Date:** 2026-10-06
**Supersedes (in part):** [ADR 0024](0024-mac-mini-dedicated-ollama-host.md) — its "two independent Ollama hosts" end state. ADR 0024's core decision (Mac Mini as a native-macOS Ollama host outside k3s) stands.
**Related to:** [EdgeNest PRD](../product/edgenest-prd.md) §11.2 / track T1 / §33 D1 (this ADR gates PRD Phase 3, creative jobs), [ADR 0018](0018-comfyui-memory-limit-oom-root-cause.md) (ComfyUI memory limits), [ADR 0005](0005-ollama-over-llama-cpp.md)

## Context

`gpu-node-01` has one GPU (RTX 5060 Ti, 16GB), and `nvidia.com/gpu` is a whole-device resource: at any time it belongs to **either** the k8s Ollama Deployment **or** ComfyUI. Switching between them is a manual `replicas: 0/1` toggle documented in `infra/k8s/base/comfyui/README.md`. As of the 2026-08-25 audit, Ollama holds it and ComfyUI is at 0.

ADR 0024 added the Mac Mini M6 as a second Ollama host and left the routing split between the two as an open follow-up. The Mac Mini is now built (2026-10-05): Apple M6, 32GB unified memory, Ollama 0.35.1 as a system LaunchDaemon on `192.168.0.174:11434` (`infra/mac-mini/`), measured ~20 tok/s on `qwen2.5:14b`.

The EdgeNest PRD then made the toggle a real blocker: phone → homelab image/video generation (PRD Phase 3) needs ComfyUI to be **permanently** schedulable. A user on a phone can't be asked to flip replica counts first, and having the agent flip them automatically would break chat for every Ollama consumer for the duration of a video job.

Current consumers of `gpu-node-01`'s Ollama — all three address it by the same in-cluster DNS name, `http://ollama.ollama.svc.cluster.local:11434`:
- Open WebUI (`OLLAMA_BASE_URL` in `infra/k8s/base/ollama-openwebui/02-open-webui.yaml`)
- n8n AI Agent workflow (`hybrid-local-claude-agent.json`, Ollama credential `baseUrl`, model `qwen2.5:14b`)
- n8n Telegram bot workflow (`telegram-ollama-bot.json`, HTTP Request URL)

## Decision

1. **The Mac Mini becomes the sole always-on Ollama host.** The k8s Ollama Deployment on `gpu-node-01` is scaled to `replicas: 0` and stays there.
2. **ComfyUI is scaled to `replicas: 1` permanently** and owns the RTX. The manual toggle is retired from normal operation.
3. **Consumers are migrated by repointing the existing Service, not by editing consumers.** The `ollama` Service in the `ollama` namespace keeps its name and port but becomes a **selector-less Service with a manually managed EndpointSlice** targeting `192.168.0.174:11434`. Every consumer keeps resolving `ollama.ollama.svc.cluster.local:11434` and transparently lands on the Mac Mini.
4. **The `gpu-node-01` Ollama Deployment and its model PVC are kept, not deleted**, as a manual cold fallback (see Consequences).

## Rationale

**Why consolidate rather than split (ADR 0024's open question):** any split that keeps Ollama on the RTX keeps the toggle, and the toggle is exactly what blocks Phase 3. The Mac Mini can carry the interactive + agent load on its own at this scale (single user, one primary ~14B model resident).

**Why a selector-less Service + EndpointSlice rather than ExternalName or editing consumers:**
- Zero consumer changes: no Open WebUI env edit, no n8n credential or workflow edits, no re-import.
- `ExternalName` needs a DNS name; the only LAN name would be an AdGuard rewrite, which CoreDNS can't see (CoreDNS upstream is pinned to 1.1.1.1/8.8.8.8 per ADR 0010). A raw IP endpoint avoids depending on that.
- Reverting is a manifest change: restore the selector, scale the Deployment back up.
- The Mac Mini IP is a router DHCP reservation (2026-10-05), so a hardcoded endpoint IP is stable.

**Why keep the old Deployment:** the Mac Mini is a single point of failure for local LLM inference. A pre-built fallback that can be brought back by restoring the Service selector and running the old toggle costs only disk space.

## Model set on the Mac Mini

`gpu-node-01`'s Ollama PVC currently holds `gemma3:4b`, `qwen2.5vl:7b`, `qwen2.5:14b`, `llama3.1:8b`, `batiai/qwen3.6-27b`. Pull onto the Mac Mini what consumers actually use:

| Model | Keep? | Why |
|---|---|---|
| `qwen2.5:14b` | ✅ (already pulled) | n8n AI Agent model; EdgeNest primary reasoning candidate |
| `gemma3:4b` | ✅ | Light/fast chat in Open WebUI |
| `qwen2.5vl:7b` | ✅ | Only vision-capable model (Open WebUI image input) |
| `llama3.1:8b` | optional | General chat; redundant with the above |
| `batiai/qwen3.6-27b` | ❌ | ~27B won't coexist with anything else in 32GB unified memory (PRD §11.1); available via the fallback if ever needed |

Ollama loads and unloads models on demand, so keeping several on disk is fine. The limit is what is *resident* at once.

## Consequences

- **The GPU toggle is gone from normal operation.** ComfyUI is always ready; PRD Phase 3 is unblocked.
- **Chat performance changes.** The Mac Mini runs the 14B model at ~20 tok/s; the RTX's numbers on the same model should be captured before the cutover for an honest comparison. Open WebUI users (just Deepesh) may notice the difference either way.
- **Single point of failure.** If the Mac Mini is down, every Ollama consumer fails. Mitigations: Uptime Kuma monitor on `192.168.0.174:11434`; documented manual fallback (restore selector + scale up `gpu-node-01` Ollama + scale down ComfyUI). EdgeNest's high-privacy rule (PRD §10.1) means it reports "homelab unavailable" rather than falling back to cloud.
- **Cross-machine traffic:** inference now leaves the cluster over the LAN (`control-plane-01` → TP-Link AP switch → Mac Mini, all wired). Negligible for token streams.
- **Ollama on the Mac Mini has no auth**, same as today's in-cluster Ollama, and no firewall (macOS firewall off). Unchanged LAN-only posture per ADR 0024. It's now one hop more exposed (LAN rather than cluster-internal + NodePort), which is accepted.
- **Two places to manage models during transition**, until the fallback PVC is either pruned or explicitly left frozen.
- `gpu-node-01` workloads after this: ComfyUI + exporters only. The deferred "taint `gpu-node-01`" question (CLAUDE.md, backlog #9) gets simpler: everything there is GPU-related now.

## Migration plan

1. **Baseline:** record tok/s for `qwen2.5:14b` and `gemma3:4b` on the current RTX Ollama.
2. **Pull models on the Mac Mini:** `gemma3:4b`, `qwen2.5vl:7b` (+ `llama3.1:8b` if wanted).
3. **Verify reachability from inside the cluster:** `kubectl run` a curl pod on `control-plane-01` → `http://192.168.0.174:11434/api/tags`.
4. **Repoint the Service** (manifest change in `infra/k8s/base/ollama-openwebui/01-ollama.yaml`): remove `selector`, add an `EndpointSlice` (`kubernetes.io/service-name: ollama`) with address `192.168.0.174`, port `11434`.
5. **Scale:** Ollama Deployment → 0, ComfyUI → 1.
6. **Verify each consumer:** Open WebUI text chat (`gemma3:4b`) + image input (`qwen2.5vl:7b`); n8n AI Agent including a Claude-escalation path; Telegram bot round-trip.
7. **Add Uptime Kuma monitor** for the Mac Mini's Ollama.
8. **Docs:** update `ollama-openwebui`, `comfyui`, and `n8n` READMEs (remove the "scale Ollama up first" instructions, document the fallback); update CLAUDE.md; mark ADR 0024's routing follow-up resolved by this ADR.

## Follow-ups

- [ ] Execute migration plan above.
- [ ] Uptime Kuma monitor for `192.168.0.174:11434`.
- [ ] Decide after ~1 month whether to prune the `gpu-node-01` Ollama PVC or keep it as the frozen fallback.
- [ ] Revisit backlog #9 (taint `gpu-node-01`) now that it only runs GPU workloads.
