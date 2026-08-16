# Self-Hosted Data & AI Infrastructure Platform

A self-hosted, Kubernetes-based data and ML engineering homelab. It runs local AI workloads (LLM serving, GPU-scheduled inference, agentic pipelines) on incrementally-scaled hardware, and doubles as a portfolio artifact demonstrating platform-level infrastructure skills beyond notebook-only ML work.

## Structure

- **[`infra/`](infra/)** — cluster and node infrastructure: bootstrap scripts, Kubernetes manifests (Cilium CNI, CloudNativePG, GPU scheduling), and ML serving deployments (Ollama, Open-WebUI).
- **[`agents/`](agents/)** — agentic AI work built on LangChain / LangGraph, including NLP-to-SQL agents.
- **[`docs/`](docs/)** — architecture notes, hardware evaluations, and decision records (ADRs).

## Design philosophy

Start small, scale incrementally. Hardware and infrastructure are added to match the current phase's actual needs — not anticipated future load. See [`docs/decisions/`](docs/decisions/) for the reasoning behind each hardware and architecture choice.

## Current phase

Bootstrapping compute nodes (Dell G5, GTX 1060) with stable SSH access and base OS configuration ahead of Kubernetes cluster install.

## Status

🚧 Actively under construction.
