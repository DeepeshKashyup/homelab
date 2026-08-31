# ADR 0023: Development Agent Swarm — Architecture Plan (Hybrid Claude CLI + Local Ollama Workers)

**Status:** Proposed
**Date:** 2026-08-31
**Related to:** [ADR 0022](0022-homelab-ops-agent-plan.md) (a different, unrelated agent project — that one is an infra-ops assistant for this repo; this one is a general-purpose dev-automation swarm for *any* codebase), [ADR 0019](0019-telegram-bot-webhook-cloudflare-tunnel.md) (the last time a one-time browser login had to be bootstrapped into the cluster as a Secret — same shape of problem here for Claude CLI auth)

## Context

A separate idea from ADR 0022: a swarm of agents that does real software-development work — plan a change, implement it, review it — targeting *any* codebase, not just this repo. The explicit goal is cost control: use the **Claude CLI** (`claude -p "..."`, tied to an existing subscription) instead of the Claude API for the roles that need real reasoning quality, and cheaper local Ollama models for the roles that don't need to be as capable, rather than paying API-token rates for every step of every job.

No code exists yet. This ADR captures the architecture and open risks agreed on, to build from in a future session.

## Decision

Four roles, strictly sequential (no concurrent subagents — sidesteps `gpu-node-01`'s single-GPU contention problem entirely, at the cost of wall-clock speed):

```
User submits a task + target repo
            │
            ▼
  ┌──────────────────┐
  │  Expert (Claude   │   one claude -p call: produces a
  │  CLI) — PLANNING  │   high-level plan (goals, likely
  └─────────┬─────────┘   affected files, approach, risks)
            ▼
  ┌──────────────────┐
  │ Supervisor (Ollama)│  decomposes the plan into an
  │  — DECOMPOSITION   │  ordered list of small subtasks;
  └─────────┬─────────┘  tracks state in Postgres
            │
            ▼  for each subtask, in order:
  ┌──────────────────────────────────────────┐
  │  Worker (Ollama, code-specialized model)   │
  │  — runs as an ephemeral k8s Job:            │
  │    clone target repo, agentic edit loop     │
  │    (read/edit files, run tests), produces    │
  │    a diff + summary, commits to a LOCAL      │
  │    branch only — never pushes anywhere        │
  └─────────────────┬────────────────────────┘
                     ▼
  ┌──────────────────────────────────┐
  │  Reviewer (Claude CLI) — a second   │
  │  claude -p call: reviews the diff    │
  │  against the subtask + overall plan   │
  │  → approve, or request-changes with     │
  │    specific feedback                     │
  └─────────────────┬────────────────┘
       approve │           │ request-changes (retry, max N)
               ▼           └──────────► back to Worker
     Supervisor marks subtask done,
     moves to next subtask
               │
               ▼ (all subtasks done)
     Final report to the human — a
     branch/patch to review and push
     THEMSELVES, never auto-pushed
```

## Rationale

**Why Claude CLI, not the API, for Expert/Reviewer:** uses the existing subscription instead of per-token billing — the same cost-control reasoning behind the whole Expert+Reviewer split, since Claude-quality reasoning is reserved for the two steps that most need it (planning, correctness review) rather than every step.

**Why sequential, not concurrent workers:** `gpu-node-01` has exactly one physical GPU, already manually toggled between Ollama and ComfyUI — real concurrency would mean designing around that contention from day one. Sequential execution sidesteps it entirely; revisit only if wall-clock time becomes a real problem later.

**Why a k8s Job per Worker, not a raw `docker run`:** the orchestrator itself runs as a k8s Deployment (chosen so the Claude CLI's one-time browser-login auth persists via a mounted Secret, same pattern as `cloudflared`'s tunnel credentials in ADR 0019, rather than living only on a laptop). Spinning up literal Docker containers from inside a k8s pod means either Docker-in-Docker or mounting the host's Docker socket (Docker-outside-of-Docker) — both are real, accepted patterns for CI-style workloads, but a k8s Job accomplishes the same goal (an isolated, ephemeral, destroyed-after-use container) using infrastructure and RBAC patterns this repo already has, without the added DinD/socket-mount surface. Revisit if a real reason to prefer literal Docker shows up.

**Why the Worker never pushes anywhere:** matches this repo's own git discipline all session (branch first, confirm before push) — an autonomous local model with `git push`/force-push capability to a real remote is a real risk, sandboxed container or not. The human always reviews and pushes the resulting branch/patch themselves.

## Open risks and unknowns (deliberately not glossed over)

- **Claude CLI auth mechanics inside a pod are unconfirmed.** Exactly which files/directories the CLI's login creates (config, credentials, session state) isn't yet known precisely enough to write the Secret-mounting manifest — needs a real login done first, then inspecting what actually got created, same empirical approach used for `cloudflared`'s credentials.
- **Claude CLI concurrency/rate limits under this kind of automated, repeated use aren't characterized.** Sequential execution avoids the worst of it, but a swarm processing many jobs back-to-back could still hit limits tied to the subscription plan — worth watching for once real usage starts, not assumed away.
- **Local-model code-editing reliability is the single biggest unknown, and expectations should be set honestly**: general open models are meaningfully less reliable than Claude itself at autonomous multi-file code edits. A code-specialized model (e.g. `qwen2.5-coder`, not the general chat models already loaded) should be pulled specifically for the Worker role rather than reusing what's there — and even then, the first working version of this pipeline should be expected to need real debugging/prompt-iteration, not "wire it up once and it works."
- **New k8s RBAC surface**: the orchestrator's ServiceAccount needs permission to create Jobs — a real permission expansion worth scoping tightly (a dedicated namespace, per-Job resource limits per ADR 0018's lesson, nothing close to cluster-admin) rather than granted broadly.

## Consequences

- New Postgres database/role (`swarm`), same `DatabaseRole`/`Database` CRD pattern as every other app this session — tracks jobs/subtasks/statuses/outputs, giving a real audit trail and resumability if the orchestrator pod restarts mid-job.
- New k8s Deployment (`infra/k8s/base/dev-agent-swarm/`, name TBD), pinned to `control-plane-01`, non-GPU — calls Ollama's existing Service for Supervisor/Worker reasoning, `claude` CLI in-pod for Expert/Reviewer.
- A genuinely separate effort from ADR 0022's Ops Agent — the two share the "local model + Claude escalation" philosophy first proven in backlog #17, but nothing else; no reason to build them as one system.

## Follow-ups

- [ ] Do a real `claude` CLI login (on this Mac or another machine), inspect exactly what auth state it creates, package into a k8s Secret.
- [ ] Pull a code-specialized Ollama model (e.g. `qwen2.5-coder`) for the Worker role.
- [ ] Design the Postgres schema for job/subtask state tracking.
- [ ] Build the orchestrator (Expert call → Supervisor decomposition → per-subtask Worker Job → Reviewer call loop), sequential only, no concurrency yet.
- [ ] Scope the Worker Job's RBAC tightly; confirm Workers never get real push/network-egress-to-remotes capability beyond what a sandboxed clone needs.
- [ ] Run a real end-to-end test job against a throwaway repo before trusting it on anything that matters.
