# CLAUDE.md

## Purpose & context

Deepesh is building a self-hosted, Kubernetes-based data and ML engineering homelab platform. The project serves dual purposes: a functional infrastructure for running local AI workloads, and a portfolio artifact to strengthen a senior/platform-oriented data & ML engineering profile (moving beyond a notebook-only ML background).

The stack spans infrastructure (Kubernetes, Cilium CNI, CloudNativePG), ML serving (Ollama, Open-WebUI, GPU scheduling), and agentic AI work (LangChain, LangGraph, NLP-to-SQL agents). The platform is being developed incrementally, with a phased hardware expansion strategy that started from a single existing compute node (a Dell G5 with a GTX 1060) and has since grown to a small three-node cluster plus a dedicated infra/services box (see Current state).

## Current state

Hardware expansion phase 1 is done — two additional nodes have been purchased, moving the platform from one box to a small dedicated cluster:

- **PC 1 — `gpu-node-01` (~$800):** AMD Ryzen 7 5700G w/ Radeon Graphics (16 threads), 32GB DDR4 RAM, 512GB SSD, NVIDIA GeForce RTX 5060 Ti (16GB VRAM). Ubuntu 26.04 LTS, NVIDIA driver already working (595.84 / CUDA 13.2). Runs GPU-scheduled ML workloads (Ollama, ComfyUI). Static IP `192.168.0.79`, now on wired Ethernet — cable freed up from `infra-node-01`'s switch to Wi-Fi (2026-08-21, see below).
- **PC 2 — `control-plane-01`:** HP ProDesk G5 800, Intel i5, 32GB DDR4 RAM, 1TB SSD, on Wi-Fi via USB adapter. Hosts the K8s control plane and general app workloads. Static IP `192.168.0.106`. (Renamed from a generic default hostname `homelab-01` to avoid confusion — its model name "G5" is coincidentally similar to the Dell G5 below but is an unrelated machine.)
- **Dell G5 (GTX 1060)** — original baseline node; will **not** join the Kubernetes cluster. Runs **Windows** (not Linux, unlike the other nodes) and is repurposed as the admin/jump box: PowerShell + Windows' built-in OpenSSH client, used to SSH into cluster nodes, install software, and access apps running on the cluster.
- **`infra-node-01` (Lenovo ThinkCentre M700 Tiny):** i3-6100T (2C/4T, 35W TDP), 8GB RAM, 100GB SSD, Ubuntu Server. Static IP `192.168.0.82`, now reached over Wi-Fi rather than Ethernet (see below). Deliberately **not** joining the k3s cluster — dedicated to infrastructure/network services instead (local DNS first — resolves the open `docs/decisions/0009` follow-up on standing up local DNS before the NodePort→Traefik Ingress migration; monitoring and other small always-on services later). Its low power draw (35W T-series CPU) makes it a natural fit for a 24/7 role. SSH bootstrap in progress as of 2026-08-21.

**`infra-node-01` switched from Ethernet to Wi-Fi (2026-08-21)**, freeing its Ethernet cable for `gpu-node-01`, which had no working wired connection until this swap. Its Wi-Fi interface (`wlp1s0`) is configured with a **static address set directly in netplan** (`/etc/netplan/01-wifi-config.yaml`) rather than via router DHCP reservation like the other nodes — the router kept renewing the node's prior dynamic Wi-Fi lease instead of honoring a reservation retargeted to the Wi-Fi MAC, even across a router reboot, so netplan-level static addressing was used instead to sidestep that. The original `eno1` (Ethernet) netplan config was left in place but is now unused (`eno1` shows `NO-CARRIER`) — a one-cable-swap revert path if Wi-Fi ever needs to be undone. DNS on the node is pinned to `1.1.1.1`/`8.8.8.8`, matching the reasoning in `docs/decisions/0010` (avoid depending on a Wi-Fi-provided DNS server that may be unreachable in practice).

This supersedes the earlier used-GPU-market evaluation (RTX 4070 Ti Super / used prebuilt / RTX 5070 Ti system — see `docs/decisions/0001`): rather than bolting a standalone GPU onto the existing Dell G5, Deepesh went with a dedicated GPU node plus a separate control-plane node, giving cleaner workload isolation (control plane kept off the GPU box).

**SSH bootstrap is complete** for both cluster nodes: OpenSSH installed and enabled, static IPs set via router DHCP reservation (by MAC), key-based auth set up from the Dell G5 jump box (`~/.ssh/homelab_ed25519`, no passphrase — ed25519 keypair generated in PowerShell, copied via `Get-Content | ssh ... >> authorized_keys` since Windows has no `ssh-copy-id`), and both nodes hardened to key-only auth (password + root login disabled via an `sshd_config.d` drop-in) with no lockouts.

**k3s cluster is up**: `control-plane-01` runs the k3s server (bundled flannel CNI per `docs/decisions/0007`), and `gpu-node-01` has joined as a worker — `kubectl get nodes` confirms both `Ready`. Bootstrap/install scripts live in `infra/bootstrap/` and `infra/k8s/`. Five gaps hit and fixed along the way, all now folded into the scripts so they don't recur: `control-plane-01` was missing `curl` (`infra/bootstrap/install-base-packages.sh` now covers general tooling, including `conntrack` for network debugging); `ufw` was blocking the k3s API/flannel/kubelet ports workers need on `control-plane-01` (now opened by `infra/k8s/install-k3s-server.sh`); configuring the NVIDIA containerd runtime on an unseeded config template broke CNI entirely (`docs/decisions/0008` — `infra/k8s/configure-nvidia-runtime.sh` now seeds from k3s's own generated config first); CoreDNS inherited an unreachable IPv6 DNS server from `control-plane-01`'s Wi-Fi DHCP lease, timing out in-cluster external lookups (`docs/decisions/0010` — `infra/k8s/install-k3s-server.sh` now pins CoreDNS's upstream to 1.1.1.1/8.8.8.8 and force-restarts the CoreDNS pod); and `gpu-node-01` never had its `ufw` opened at all (only `control-plane-01`'s was, asymmetrically), silently blocking every cross-node Service/pod request *into* `gpu-node-01` while the reverse direction worked fine — `docs/decisions/0011` — `infra/k8s/join-k3s-agent.sh` now opens the same ports as the server script. `docs/decisions/0010` and `0011` are both written as teaching docs, not just fix logs — worth reading if Kubernetes networking is unfamiliar territory.

**GPU scheduling is validated end to end**: `nvidia.com/gpu` is allocatable on `gpu-node-01`, and a smoke-test pod (`infra/k8s/smoke-tests/gpu-smoke-test.yaml`) ran `nvidia-smi` inside a container via the scheduler + device plugin + NVIDIA container runtime, correctly showing the RTX 5060 Ti (driver 595.84, CUDA 13.2). See `docs/decisions/0008`.

**Ollama + Open WebUI are fully working end to end**: Ollama running GPU-scheduled on `gpu-node-01`, Open WebUI on `control-plane-01`, both in the `ollama` namespace (`infra/k8s/base/ollama-openwebui/`). Reachable from the Dell G5 browser at `http://192.168.0.106:30080` (NodePort, per `docs/decisions/0009`) — Open WebUI's connection to Ollama was blocked by the DNS (`0010`) and asymmetric-firewall (`0011`) incidents above; both fixed. Confirmed working: text chat with `gemma3:4b` (after fixing its Open WebUI "Function Calling: Native" setting — that model has no tools capability, see the `ollama-openwebui` README's "gotcha" section) and image input with `qwen2.5vl:7b` (vision-capable model).

**Resolved**: `gpu-node-01`'s pre-existing native `ollama.service` (found running outside Kubernetes, predating this project's k3s work) has been fully removed — its 3 models (`qwen2.5:14b`, `llama3.1:8b`, `batiai/qwen3.6-27b`) were migrated into the Kubernetes-managed Ollama's PVC first (`infra/k8s/migrate-and-remove-native-ollama.sh`), then the native service, binary, data dir, and dedicated system user/group were deleted. Confirmed clean via `systemctl status ollama` (unit not found).

**ComfyUI is working**: `infra/k8s/base/comfyui/`, GPU-scheduled on `gpu-node-01` (same single-GPU constraint as Ollama — see that directory's README for the manual scale-up/down toggle between the two; currently `comfyui` is at `replicas: 1` and `ollama` at `replicas: 0`). First deploy of `ghcr.io/ai-dock/comfyui:latest-cuda` hit three separate problems — a public-tunnel security incident, Kubernetes-incompatible port automation, and a bundled PyTorch too old for the RTX 5060 Ti's Blackwell architecture — full writeup in `docs/decisions/0012`. Switched to `yanwk/comfyui-boot:cu130-slim-v2` (plain ComfyUI, no bundled extras, explicit Blackwell support) and confirmed image generation working end to end with the `z_image_turbo` model (VAE + text encoder + diffusion model, pulled via `wget` directly into the pod — note: HuggingFace file URLs need `/resolve/main/...` not `/blob/main/...`, the latter downloads an HTML preview page instead of the actual weights).

## Operating rules

- Use the short SSH aliases from the Dell G5 jump box: `ssh gpu-node-01` and `ssh control-plane-01`.
- Do not run any installation or bootstrap commands on the cluster nodes without explicit user permission. This includes k3s installation, package installs, system updates, package repository changes, and any `curl ... | sh` style installer flows.
- Before any installation task, confirm the exact command and intent with the user, and wait for approval before executing it.
- Never manually suspend/sleep `gpu-node-01` (or `control-plane-01`) — power it off (`shutdown`/`poweroff`) instead when it needs to go offline. Incident on 2026-08-19/20: a manual suspend at 08:25 hit an NVIDIA driver error (`NV_ERR_NO_MEMORY` during `nvidia-suspend.service`) that silently corrupted the GPU driver's internal state; the node was unreachable for ~14 hours until resumed, and hours later a heavy workload (dual 14B Wan 2.2 video generation) hit that corrupted state and hung the GPU completely — no display output, no fan response, `nvidia-smi` unresponsive — requiring a hard power-off to recover. A clean shutdown/reboot doesn't have this failure mode.

On the portfolio side, Deepesh has drafted resume bullet points for a project section titled "Self-Hosted Data & AI Infrastructure Platform." The repo is now live and public on GitHub: **https://github.com/DeepeshKashyup/homelab** — pushed from PC 1 via a dedicated SSH deploy key (`~/.ssh/github_ed25519` on PC 1, separate from the jump-box-to-node key), with `/infra`, `/agents`, and `/docs` directories (hardware inventory + ADRs under `docs/`, working SSH bootstrap scripts under `infra/bootstrap/`).

## On the horizon

- Installing the Kubernetes control plane on PC 2 and joining PC 1 as a GPU-scheduled worker — done
- Migrating the CNI from bundled flannel to Cilium (see `docs/decisions/0007`), before real workloads are deployed
- Validating GPU availability/scheduling in Kubernetes on `gpu-node-01` (NVIDIA device plugin) — done, including an end-to-end `nvidia-smi` smoke test
- Installing Ollama on `gpu-node-01` and Open WebUI on `control-plane-01`, exposed via NodePort for now (see `docs/decisions/0009`) — done, fully working end to end (text + vision models tested)
- Reconciling the pre-existing native `ollama.service` on `gpu-node-01` — done, migrated and removed
- Redeploying ComfyUI with the fixed manifest — done, image generation confirmed working with `z_image_turbo`
- Auditing what's actually running/exposed on both nodes (`kubectl get pods -A`, Service types) given the ComfyUI exposure incident — don't assume the repo's manifests are the complete picture
- Deciding whether to taint `gpu-node-01` so it's reserved for GPU/inference workloads only — today nothing stops the scheduler from placing ordinary non-GPU pods there if `control-plane-01` runs low on resources, which would contend with Ollama for CPU/RAM even without touching the GPU. Deliberately deferred until real workloads make the risk concrete rather than hypothetical. (Open WebUI is explicitly pinned to `control-plane-01` via `nodeSelector` as a first, narrow step in this direction.)
- Bootstrapping `infra-node-01` (the new M700): SSH key-based auth + hardening + base packages, matching the `infra/bootstrap/` flow already used for the other two nodes — in progress. Then standing up local DNS (AdGuard Home or Pi-hole) as its first service, resolving the open `docs/decisions/0009` follow-up.
- Investigating the GPU hang incidents on `gpu-node-01` (2026-08-19/20, recurred 2026-08-20/21) — first tied to a manual suspend corrupting the NVIDIA driver (see the "never suspend" operating rule below), but it recurred on a clean boot without a suspend involved, during the heaviest workload yet (dual 14B Wan 2.2 video generation). Root cause not yet confirmed — candidates are sustained-load instability, residual effects from the first incident, or a hardware issue with the card. Plan: ease back in with light workloads first and watch closely (`nvidia-smi` monitoring) before attempting heavy video generation again; consider a warranty/return conversation if it keeps recurring.
- Standing up local DNS and migrating from NodePort to Traefik Ingress (see `docs/decisions/0009`) once more than 1–2 apps need LAN exposure
- Deploying n8n on `control-plane-01`
- Exposing local model access outside the home network via a Telegram bot — the bot would poll/connect outbound to Telegram's API from inside the cluster and call Ollama's internal Service directly, so no inbound port-forwarding, dynamic DNS, or public TLS cert is needed on the home network. Lets Deepesh query local models from a phone. Not started; a natural extension once Ollama + Open WebUI are stable.
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
