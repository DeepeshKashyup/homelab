# ADR 0005: Local Model Runtime Choice — Ollama over llama.cpp

**Status:** Accepted
**Date:** 2026-08-18

## Context

The homelab is being built around a hybrid AI pattern: local models run on the GPU node for low-latency, low-cost, privacy-sensitive work; cloud models such as Claude are used for deeper reasoning or fallback. The local runtime must be easy to operate, easy to integrate with automation tools, and stable enough to support a small self-hosted AI stack without requiring constant low-level tuning.

This project is intentionally designed around the smallest useful working AI platform, not a custom model-serving stack from scratch. We need a runtime that can support:
- local LLM inference on the GPU node
- use from automation tools such as n8n or agent orchestration code
- use from Open WebUI or similar UIs
- simple integration with local workflows and cloud model routing

## Options considered

1. **Ollama**
   - Very fast path to running local models
   - Simple HTTP API and good ecosystem tooling
   - Easy to integrate with automation, UI layers, and agent apps
   - Lower operational overhead for a homelab
   - Fits the current project goal of getting a working hybrid local/cloud stack quickly

2. **llama.cpp**
   - Extremely capable low-level inference engine
   - Strong flexibility and deep control over model serving details
   - More manual setup and integration burden
   - Requires more operational attention for a small home-lab project
   - Better suited when a custom runtime pipeline is the direct goal rather than a fast path to a usable platform

## Decision

Use **Ollama** as the local model runtime for the homelab.

We will keep llama.cpp as a potential future option only if a specific requirement emerges that demands lower-level control or a custom inference setup. For the current phase, Ollama is the right default choice.

## Rationale

- The project priorities are speed to value, reliability, and simple integration, not custom inference-engine engineering.
- Ollama gives a clean way to run smaller local models on the GPU node and expose them to apps and agents with minimal friction.
- The system design includes hybrid model routing: local models for fast tasks, cloud models for heavier reasoning. Ollama is a better fit for that orchestration model.
- We expect to run local models from n8n, Open WebUI, and agent workflows; Ollama’s API-first experience aligns well with those needs.
- `llama.cpp` remains valuable, but it is not the best first choice when the goal is a working local + cloud AI system within a small self-hosted cluster.

## Consequences

- We can bring up local model serving quickly on `gpu-node-01` without building a custom inference stack.
- The control-plane apps and automation layer can integrate with a stable local API surface.
- The project remains aligned with the incremental, low-risk design philosophy.
- If future workload requirements demand more low-level tuning, we can evaluate `llama.cpp` then rather than prematurely optimizing the runtime now.

## Follow-ups

- [ ] Install and validate Ollama on `gpu-node-01`
- [ ] Expose local model serving to control-plane apps
- [ ] Connect Open WebUI and n8n to the local Ollama runtime
- [ ] Validate hybrid local + Claude reasoning flows in a simple agent or workflow
