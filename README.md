# Self-Hosted Data & AI Infrastructure Platform

A self-hosted, Kubernetes-based data and ML engineering homelab. It runs local AI workloads (LLM serving, GPU-scheduled inference, agentic pipelines) on incrementally-scaled hardware, and doubles as a portfolio artifact demonstrating platform-level infrastructure skills beyond notebook-only ML work.

## Structure

- **[`infra/`](infra/)** — cluster and node infrastructure: bootstrap scripts, Kubernetes manifests (Cilium CNI, CloudNativePG, GPU scheduling), ML serving deployments (Ollama, Open-WebUI, ComfyUI), and media serving (Plex).
- **[`agents/`](agents/)** — agentic AI work built on LangChain / LangGraph, including NLP-to-SQL agents.
- **[`docs/`](docs/)** — architecture notes, hardware evaluations, and decision records (ADRs).

## Design philosophy

Start small, scale incrementally. Hardware and infrastructure are added to match the current phase's actual needs — not anticipated future load. See [`docs/decisions/`](docs/decisions/) for the reasoning behind each hardware and architecture choice.

## Current phase

A k3s cluster is up and running across two dedicated nodes (`control-plane-01`, `gpu-node-01`), with GPU scheduling validated end to end. Ollama + Open WebUI and ComfyUI are both deployed and working; Plex Media Server deployment is in progress. A third, dedicated node (`infra-node-01`) runs always-on infrastructure services (local DNS via AdGuard Home) outside the cluster. See `CLAUDE.md` and [`docs/decisions/`](docs/decisions/) for the full incremental build-out and the real issues hit (and fixed) along the way.

## Status

🚧 Actively under construction — core ML serving is working; media serving is in progress; Cilium CNI, CloudNativePG, and the agentic AI work are still ahead.
