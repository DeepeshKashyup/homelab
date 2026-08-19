# CLAUDE.md

## Purpose & context

Deepesh is building a self-hosted, Kubernetes-based data and ML engineering homelab platform. The project serves dual purposes: a functional infrastructure for running local AI workloads, and a portfolio artifact to strengthen a senior/platform-oriented data & ML engineering profile (moving beyond a notebook-only ML background).

The stack spans infrastructure (Kubernetes, Cilium CNI, CloudNativePG), ML serving (Ollama, Open-WebUI, GPU scheduling), and agentic AI work (LangChain, LangGraph, NLP-to-SQL agents). The platform is being developed incrementally, with a phased hardware expansion strategy that started from a single existing compute node (a Dell G5 with a GTX 1060) and has since grown to a small three-node cluster (see Current state).

## Current state

Hardware expansion phase 1 is done — two additional nodes have been purchased, moving the platform from one box to a small dedicated cluster:

- **PC 1 — `gpu-node-01` (~$800):** AMD Ryzen 7 5700G w/ Radeon Graphics (16 threads), 32GB DDR4 RAM, 512GB SSD, NVIDIA GeForce RTX 5060 Ti (16GB VRAM). Ubuntu 26.04 LTS, NVIDIA driver already working (595.84 / CUDA 13.2). Will run GPU-scheduled ML workloads (Ollama inference, etc.). Static IP `192.168.0.79`.
- **PC 2 — `control-plane-01`:** HP ProDesk G5 800, Intel i5, 32GB DDR4 RAM, 1TB SSD, on Wi-Fi via USB adapter. Will host the K8s control plane and general app workloads. Static IP `192.168.0.106`. (Renamed from a generic default hostname `homelab-01` to avoid confusion — its model name "G5" is coincidentally similar to the Dell G5 below but is an unrelated machine.)
- **Dell G5 (GTX 1060)** — original baseline node; will **not** join the Kubernetes cluster. Runs **Windows** (not Linux, unlike PC 1/PC 2) and is repurposed as the admin/jump box: PowerShell + Windows' built-in OpenSSH client, used to SSH into cluster nodes, install software, and access apps running on the cluster.

This supersedes the earlier used-GPU-market evaluation (RTX 4070 Ti Super / used prebuilt / RTX 5070 Ti system — see `docs/decisions/0001`): rather than bolting a standalone GPU onto the existing Dell G5, Deepesh went with a dedicated GPU node plus a separate control-plane node, giving cleaner workload isolation (control plane kept off the GPU box).

**SSH bootstrap is complete** for both cluster nodes: OpenSSH installed and enabled, static IPs set via router DHCP reservation (by MAC), key-based auth set up from the Dell G5 jump box (`~/.ssh/homelab_ed25519`, no passphrase — ed25519 keypair generated in PowerShell, copied via `Get-Content | ssh ... >> authorized_keys` since Windows has no `ssh-copy-id`), and both nodes hardened to key-only auth (password + root login disabled via an `sshd_config.d` drop-in) with no lockouts.

**k3s cluster is up**: `control-plane-01` runs the k3s server (bundled flannel CNI per `docs/decisions/0007`), and `gpu-node-01` has joined as a worker — `kubectl get nodes` confirms both `Ready`. Bootstrap/install scripts live in `infra/bootstrap/` and `infra/k8s/`. Two gaps hit and fixed along the way, both now folded into the scripts so they don't recur: `control-plane-01` was missing `curl` (SSH bootstrap only ever installed SSH-specific packages — `infra/bootstrap/install-base-packages.sh` now covers general tooling), and `ufw` was blocking the k3s API/flannel/kubelet ports workers need (6443/tcp, 8472/udp, 10250/tcp — now opened by `infra/k8s/install-k3s-server.sh` itself).

## Operating rules

- Use the short SSH aliases from the Dell G5 jump box: `ssh gpu-node-01` and `ssh control-plane-01`.
- Do not run any installation or bootstrap commands on the cluster nodes without explicit user permission. This includes k3s installation, package installs, system updates, package repository changes, and any `curl ... | sh` style installer flows.
- Before any installation task, confirm the exact command and intent with the user, and wait for approval before executing it.

On the portfolio side, Deepesh has drafted resume bullet points for a project section titled "Self-Hosted Data & AI Infrastructure Platform." The repo is now live and public on GitHub: **https://github.com/DeepeshKashyup/homelab** — pushed from PC 1 via a dedicated SSH deploy key (`~/.ssh/github_ed25519` on PC 1, separate from the jump-box-to-node key), with `/infra`, `/agents`, and `/docs` directories (hardware inventory + ADRs under `docs/`, working SSH bootstrap scripts under `infra/bootstrap/`).

## On the horizon

- Installing the Kubernetes control plane on PC 2 and joining PC 1 as a GPU-scheduled worker — done
- Migrating the CNI from bundled flannel to Cilium (see `docs/decisions/0007`), before real workloads are deployed
- Validating GPU availability/scheduling in Kubernetes on `gpu-node-01` (NVIDIA device plugin)
- Installing Ollama on `gpu-node-01` and exposing model serving to control-plane apps
- Deploying Open WebUI and n8n on `control-plane-01`
- Adding a `~/.ssh/config` block on the Dell G5 for short hostnames (`ssh gpu-node-01` / `ssh control-plane-01`) — done
- Cloning the repo onto PC 2 and the Dell G5 (currently only pushed from PC 1) so changes don't have to be relayed manually
- Considering wired Ethernet for PC 2 (currently Wi-Fi via USB adapter) given its control-plane role
- Writing the portfolio README/walkthrough now that the repo is public (strong README, written walkthrough, optional demo video, LinkedIn project entries)
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
- **Current compute nodes**: Dell G5 (GTX 1060, Windows, admin/jump box — not in cluster) · `gpu-node-01` / PC 1 (Ryzen 7 5700G, RTX 5060 Ti 16GB, Ubuntu 26.04, `192.168.0.79`) · `control-plane-01` / PC 2 (HP ProDesk G5 800, i5, Ubuntu, `192.168.0.106`)
