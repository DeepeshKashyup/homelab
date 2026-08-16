# CLAUDE.md

## Purpose & context

Deepesh is building a self-hosted, Kubernetes-based data and ML engineering homelab platform. The project serves dual purposes: a functional infrastructure for running local AI workloads, and a portfolio artifact to strengthen a senior/platform-oriented data & ML engineering profile (moving beyond a notebook-only ML background).

The stack spans infrastructure (Kubernetes, Cilium CNI, CloudNativePG), ML serving (Ollama, Open-WebUI, GPU scheduling), and agentic AI work (LangChain, LangGraph, NLP-to-SQL agents). The platform is being developed incrementally, with a phased hardware expansion strategy that started from a single existing compute node (a Dell G5 with a GTX 1060) and has since grown to a small three-node cluster (see Current state).

## Current state

Hardware expansion phase 1 is done — two additional nodes have been purchased, moving the platform from one box to a small dedicated cluster:

- **PC 1 — GPU workload node (~$800):** AMD Ryzen 7 5700G w/ Radeon Graphics (16 threads), 32GB DDR4 RAM, 512GB SSD, NVIDIA GeForce RTX 5060 Ti (16GB VRAM). Will run GPU-scheduled ML workloads (Ollama inference, etc.).
- **PC 2 — App / Kubernetes control-plane node:** HP ProDesk G5 800, Intel i5, 32GB DDR4 RAM, 1TB SSD. Will host the K8s control plane and general app workloads.
- **Dell G5 (GTX 1060)** — original baseline node; will **not** join the Kubernetes cluster. Repurposed as the admin/jump box: used to SSH into cluster nodes, install software, and access apps running on the cluster.

This supersedes the earlier used-GPU-market evaluation (RTX 4070 Ti Super / used prebuilt / RTX 5070 Ti system — see `docs/decisions/0001`): rather than bolting a standalone GPU onto the existing Dell G5, Deepesh went with a dedicated GPU node plus a separate control-plane node, giving cleaner workload isolation (control plane kept off the GPU box). Note: "PC 2 — HP ProDesk **G5** 800" shares the "G5" label with the original **Dell G5** baseline node by coincidence — worth using unambiguous hostnames when bootstrapping to avoid confusion.

Immediate next step: get both new nodes on the network with stable SSH access, then bootstrap them (base OS, NVIDIA drivers on PC 1) ahead of Kubernetes install.

On the portfolio side, Deepesh has drafted resume bullet points for a project section titled "Self-Hosted Data & AI Infrastructure Platform" and has scaffolded the GitHub portfolio repo with `/infra`, `/agents`, and `/docs` directories (including hardware inventory and ADRs under `docs/`).

## On the horizon

- Stable SSH + base bootstrap for PC 1 and PC 2
- Installing the Kubernetes control plane on PC 2 and joining PC 1 as a GPU-scheduled worker
- Completing and publishing the GitHub portfolio (strong README, written walkthrough, optional demo video, LinkedIn project entries)
- Identifying real workload bottlenecks to guide any further hardware expansion

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
- **Current compute nodes**: Dell G5 (GTX 1060, admin/jump box — not in cluster) · PC 1 GPU node (Ryzen 7 5700G, RTX 5060 Ti 16GB) · PC 2 control-plane node (HP ProDesk G5 800, i5)
