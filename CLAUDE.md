# CLAUDE.md

## Purpose & context

Deepesh is building a self-hosted, Kubernetes-based data and ML engineering homelab platform. The project serves dual purposes: a functional infrastructure for running local AI workloads, and a portfolio artifact to strengthen a senior/platform-oriented data & ML engineering profile (moving beyond a notebook-only ML background).

The stack spans infrastructure (Kubernetes, Cilium CNI, CloudNativePG), ML serving (Ollama, Open-WebUI, GPU scheduling), and agentic AI work (LangChain, LangGraph, NLP-to-SQL agents). The platform is being developed incrementally, with a phased hardware expansion strategy starting from existing compute nodes (a Dell G5 with a GTX 1060).

## Current state

Deepesh is actively evaluating used GPU hardware to expand the homelab's compute capacity. Recent evaluations:

- A standalone RTX 4070 Ti Super 16GB (~$800) was assessed as fairly priced with strong warranty documentation — aligned with the incremental scaling philosophy and considered lower risk.
- A used prebuilt (Ryzen 7 7800X3D, RTX 4070 Super 12GB, 32GB RAM) at ~$1,500 was flagged as overpriced (fair value ~$1,000–$1,150); the listing also contained a GPU naming typo.
- A higher-end system (RTX 5070 Ti, Ryzen 7 7800X, 128GB DDR5) was assessed as beyond current phase needs — purchase deferred until actual workload bottlenecks justify it.

On the portfolio side, Deepesh has drafted resume bullet points for a project section titled "Self-Hosted Data & AI Infrastructure Platform" and is working on a GitHub portfolio structure with `/infra`, `/agents`, and `/docs` directories.

## On the horizon

- Completing and publishing the GitHub portfolio (strong README, written walkthrough, optional demo video, LinkedIn project entries)
- Continuing phased hardware expansion as workloads scale
- Identifying real bottlenecks to guide the next GPU upgrade decision

## Key learnings & principles

- **Start small, scale incrementally**: Deepesh explicitly follows a "start small, incremental" homelab design philosophy — hardware purchases should match current phase needs, not anticipated future ones.
- **Standalone GPU > prebuilt** when existing compute nodes are available: lower risk, better fit for incremental expansion.
- **Used hardware red flags**: mismatched specs/typos in listings, lack of warranty documentation, no seller account history, and PSU/cooling specs unsuitable for 24/7 server use are all active evaluation criteria.
- **Portfolio framing matters**: the project should be presented as a senior/platform story with concrete technology nouns (for ATS) and only claim completed phases.

## Approach & patterns

- Hardware purchases are evaluated against current-phase requirements, not maximum possible utility — avoids over-buying.
- Resume and portfolio artifacts are being built in parallel with the technical work, not as an afterthought.
- Uses market price research (new retail comparables, component shortage context) as a baseline for used hardware negotiation.

## Tools & resources

- **Infrastructure**: Kubernetes, Cilium CNI, CloudNativePG
- **ML serving**: Ollama, Open-WebUI
- **Agentic AI**: LangChain, LangGraph
- **Portfolio**: GitHub (structured repo), LinkedIn project entries
- **Current compute baseline**: Dell G5, GTX 1060
