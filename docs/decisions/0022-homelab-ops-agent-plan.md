# ADR 0022: Homelab Ops Agent — Architecture Plan (RAG + Multi-Agent Orchestration)

**Status:** Proposed
**Date:** 2026-08-31
**Related to:** [ADR 0005](0005-ollama-over-llama-cpp.md) (Ollama as the local model runtime this builds on), backlog #17/#18 (the n8n AI Agent + Telegram bot pattern this generalizes), backlog #42/#43/#44 (the items this plan folds together / separates out)

## Context

Three backlog items (#42 RAG pipeline, #43 multi-agent orchestration, #44 fine-tuning) existed as separate, disconnected line items. Planning them together surfaced a stronger single project: this platform already has most of the pieces a real agentic system needs (Ollama serving tool-calling-capable models, a proven local-model+Claude-escalation pattern from #17, a working Telegram front door from #18, and — not originally intended as such, but genuinely useful as one — a rich corpus of real operational knowledge in this repo's own ADRs and READMEs).

No code has been written yet. This ADR captures the architecture and phased plan agreed on, to pick up in a future session rather than losing the reasoning between now and then.

## Decision

Build a **"Homelab Ops Agent"**: a multi-agent system, implemented as a standalone Python/LangGraph service (not another n8n workflow), that can answer questions about this platform's own history (RAG over its ADRs/READMEs) and act on live infrastructure (query Prometheus, manage the Vikunja backlog) — with a supervisor agent routing between specialist sub-agents.

```
                    ┌─────────────────────────────┐
                    │   Supervisor Agent (LangGraph)│
                    │   routes each query to the    │
                    │   right specialist             │
                    └───────────┬─────────────────┘
              ┌──────────────────┼──────────────────┐
              ▼                  ▼                  ▼
    ┌─────────────────┐ ┌────────────────┐ ┌─────────────────┐
    │  Docs-RAG Agent  │ │ Infra-Status    │ │  Backlog Agent   │
    │  (retrieval over │ │ Agent (tools:   │ │  (tools: Vikunja │
    │  ADRs/READMEs)   │ │ Prometheus,     │ │  API CRUD)       │
    │                  │ │ kubectl)        │ │                  │
    └─────────────────┘ └────────────────┘ └─────────────────┘
              │                  │                  │
              └──────────────────┴──────────────────┘
                                  ▼
                    escalates to Claude when a
                    specialist is out of its depth
                    (same pattern as backlog #17)
```

### Why standalone Python/LangGraph, not another n8n workflow

n8n's AI Agent node (used for #17) proved the pattern works, but it's a visual workflow tool — it doesn't produce a codebase. A real Python/LangGraph service is more work but is a genuinely stronger portfolio artifact (actual code on GitHub, not a JSON export), matches backlog #43's original literal framing, and gives real control over multi-agent state/routing that n8n's node graph doesn't expose cleanly.

### Why this repo's own docs as the RAG corpus

Zero data-collection work (the corpus already exists, 22 ADRs + a dozen READMEs), and it's *real* operational knowledge, not toy data — genuine incidents like the `template1` lock, `VIKUNJA_DATABASE_PORT` being silently ignored, the CoreDNS/asymmetric-firewall incidents, etc. "An agent that understands its own infrastructure's history" is a concrete, demoable story.

### New infrastructure this requires (each a real decision, not yet finalized)

- **Vector store**: `pgvector` on the *existing* shared Postgres cluster is the leading option — keeps this whole platform's "consolidate app state on Postgres" pattern (n8n, Open WebUI, Grafana, Vikunja all already migrated) going, rather than standing up a dedicated vector DB (Qdrant/Chroma/Milvus) as a new component to deploy and back up. Not yet confirmed whether the CNPG Postgres image has `pgvector` available — first thing to check when this work starts.
- **Embedding model**: none of the 5 currently-loaded Ollama models are embedding models. Would pull `nomic-embed-text` (small, well-supported) alongside them.
- **Interface**: as a standalone Python process, this can use Telegram's **long-polling** API directly — no webhook, no Cloudflare Tunnel needed for this specific bot, which is actually closer to backlog #18's original outbound-only design intent than the n8n webhook solution ADR 0019 had to build. Still undecided: a second, separate Telegram bot for this agent, or have the existing n8n Telegram workflow call this service instead of Ollama directly, reusing one front door.
- **Deployment**: a new k8s Deployment (`infra/k8s/base/homelab-agent/`), pinned to `control-plane-01` like every other non-GPU app in this repo — calls Ollama's existing Service rather than being a GPU workload itself.

### Phased build plan

1. **RAG foundation**: confirm/enable `pgvector`, write an ingestion script (chunk + embed every ADR/README, store in Postgres), build a bare retrieval-only endpoint. Prove retrieval quality before adding any agent logic.
2. **One working specialist**: wrap Phase 1 in an actual agent — retrieve, synthesize an answer, escalate to Claude on low-confidence/empty retrieval (same escalation pattern as #17). This alone closes backlog #42.
3. **Multi-agent supervisor**: add the infra-status and backlog specialist agents, build the LangGraph supervisor routing between all three. Closes backlog #43.
4. **Interface + deployment**: wire up Telegram (or n8n handoff, per the still-open decision above), deploy as a real k8s service, and write the follow-up ADR documenting whichever choices got made along the way (this ADR is the plan; a later one should record what was actually built, same way ADR 0012's postscript did when the real implementation diverged from the original plan).

### Why #44 (fine-tuning/LoRA) is deliberately NOT part of this

It's about improving a model, not orchestrating one — no dependency on RAG or multi-agent work, and folding it in would blur two genuinely different projects. Left as its own separate, later effort.

## Consequences

- Backlog #42 and #43 stay open but are now understood as phases of one project rather than independent items — closing one likely means closing (or substantially progressing) the other, since they share the same service/deployment.
- This introduces the platform's first vector-search workload — worth watching Postgres resource usage once built, same "every future workload should ship with explicit memory limits" lesson from ADR 0018.
- No code exists yet. This ADR's Status is `Proposed`, not `Accepted`, reflecting that — flip it once Phase 1 actually starts.

## Follow-ups

- [ ] Confirm `pgvector` availability on the CNPG Postgres image (or what it'd take to add it).
- [ ] Pull `nomic-embed-text` (or equivalent) via Ollama.
- [ ] Phase 1: ingestion script + bare retrieval endpoint.
- [ ] Phase 2: first working specialist agent (closes #42).
- [ ] Phase 3: LangGraph supervisor + remaining specialists (closes #43).
- [ ] Phase 4: interface decision (new bot vs. n8n handoff), deployment manifest, follow-up ADR recording what was actually built.
