# EdgeNest — Product Requirements Document

**Product:** EdgeNest
**Version:** v1.2 PRD
**Status:** Approved direction; Phase 0 ready to start. Three architecture decisions (§33) to be recorded as ADRs before the phases that depend on them.
**Product type:** Edge-first personal AI assistant
**Primary client:** Android phone
**Cloud:** Google Cloud Platform (Cloud Run — thin authenticated front door only)
**Edge runtime:** LiteRT
**Local inference:** Ollama on Mac mini M6 (`192.168.0.174`, ADR 0024)
**Infrastructure:** Existing k3s homelab (`control-plane-01`, `gpu-node-01`) + `infra-node-01` (outside k3s)
**GPU compute:** RTX 5060 Ti 16GB on `gpu-node-01`

### Changelog

| Version | Date | Changes |
|---|---|---|
| v1.0 | 2026-10-05 | Initial PRD. |
| v1.1 | 2026-10-06 | Post-review revision: agent runtime + Tool Gateway moved from Cloud Run into the homelab (Cloud Run becomes a stateless auth/relay); private link specified (Cloudflare Tunnel + Access, not GCP Cloud VPN); sessions/telemetry given a home (homelab Postgres + Prometheus/Grafana); routing responsibility split between phone and homelab; MVP shrunk to text + read-only tools, voice moved post-MVP; prompt-injection-aware tool policy (no auto-executed writes, no shell tool, split RBAC); offline queue limited to questions; explicit privacy fallback rule; Mac mini model plan sized to its real 32GB; topology corrected (`infra-node-01` is not in k3s); repo layout mapped onto the existing repo; Ollama consolidation and ADR 0022 overlap made explicit. |
| v1.2 | 2026-10-06 | Added Phase 3 — Creative jobs (phone → homelab image/video generation): async job API, fixed ComfyUI workflow templates, bounded parameters, serial GPU queue with health pre-check, signed-URL result delivery (§13.1, §15, §26, §28). Ollama consolidation (T1) promoted from optional parallel track to Phase 3 prerequisite. Later phases renumbered: RAG 4, tools/dashboard 5, actions 6, voice 7, routing 8. |

---

## 1. Executive Summary

**EdgeNest** is a privacy-first, edge AI personal assistant that distributes AI workloads across the user's phone, homelab, and cloud.

> **Run the task on the smallest, closest, cheapest compute resource capable of completing it.**

The phone provides immediate, offline-capable AI using a small model running through LiteRT.

When a request needs more context, tools, or reasoning, the phone sends it to a single **EdgeNest API**. That API's public front door is a thin, stateless **Cloud Run relay** in GCP whose only jobs are device authentication and forwarding. The request crosses an authenticated private link into the homelab, where the **EdgeNest Agent** (running in k3s) does the actual work: routing, reasoning, tool use, memory. It can delegate to:

- the **Mac mini M6** running Ollama (primary local reasoning + embeddings),
- the **k3s cluster** via a permissioned Tool Gateway,
- the **RTX 5060 Ti** for GPU workloads (ComfyUI/CUDA),
- or a cloud LLM, only for tasks that exceed local capabilities and only when privacy policy allows.

The user should not need to know where inference occurs — but every response is labeled with where it ran.

**Why the brain lives at home, not in GCP:** homelab data (logs, metrics, RAG documents) never needs to leave the homelab to be reasoned over, a compromise of the cloud service does not hand an attacker cluster tools, and tool calls don't each cross the internet.

---

## 2. Product Vision

Build a personal AI system that **follows the user across devices while keeping intelligence as close to the user as possible**.

```text
                       ┌──────────────────────┐
                       │   ☁️ GCP Cloud Run    │
                       │  auth + relay only   │
                       └──────────┬───────────┘
                                  │ Cloudflare Tunnel + Access
                                  │ (outbound-only from homelab)
                       ┌──────────▼───────────┐
                       │  🧠 EdgeNest Agent    │
                       │  (k3s, homelab)      │
                       └──┬────────┬───────┬──┘
                          │        │       │
                          ▼        ▼       ▼
                    🍎 Mac mini  ☸️ k3s   🖥️ RTX
                      Ollama     tools   GPU jobs
                          ▲
                          │ (via API only)
                     📱 PHONE
                   LiteRT + Edge AI
```

---

## 3. Core Principles

### P1 — Edge first
Use the phone whenever possible.

### P2 — Local second
Use the homelab before using cloud AI. Homelab data is processed in the homelab.

### P3 — Cloud last
Use cloud AI only when necessary or explicitly requested — and never for requests marked high-privacy (§10.1).

### P4 — Never expose infrastructure directly
The phone never directly controls Kubernetes, Docker, SSH, or Ollama. No homelab port is opened to the public Internet; the homelab only makes outbound connections.

### P5 — AI does not receive unrestricted shell access
All infrastructure interaction occurs through typed, permissioned tools. There is no generic shell tool at any phase.

### P6 — Compute should be invisible to the user
The user asks "Why is my GPU node unhealthy?", not "Run this on the 14B model." Visibility of *where* it ran is preserved via response labels (§21).

### P7 — Tool output is data, not instructions
Anything a tool returns (logs, events, documents) is untrusted content. It can inform an answer; it can never by itself authorize an action.

---

## 4. Target Architecture

```text
                                 INTERNET
                                     │ HTTPS
                                     ▼
                     ┌───────────────────────────────┐
                     │  GCP Cloud Run                │
                     │  EdgeNest Relay (stateless)   │
                     │  • device authentication      │
                     │  • rate limiting              │
                     │  • request_id + metadata log  │
                     │  • streaming passthrough      │
                     └───────────────┬───────────────┘
                                     │ HTTPS + Cloudflare Access service token
                                     ▼
                     ┌───────────────────────────────┐
                     │  Cloudflare Tunnel            │
                     │  (existing cloudflared, ADR   │
                     │   0019; dedicated hostname)   │
                     └───────────────┬───────────────┘
                                     │ outbound-only connection from homelab
═════════════════════════════════════╪══════════════ HOMELAB (LAN) ═════════
                                     ▼
              ┌──────────────────────────────────────────────┐
              │  EdgeNest Agent — k3s, control-plane-01      │
              │  • router (homelab vs cloud tier)            │
              │  • agent runtime                             │
              │  • Tool Gateway (policy + audit)             │
              │  • sessions, memory, telemetry → Postgres    │
              └───┬──────────────┬──────────────┬────────────┘
                  │              │              │
                  ▼              ▼              ▼
       🍎 Mac mini M6     ☸️ k3s API          🖥️ gpu-node-01
       192.168.0.174      (read-only SA;      RTX 5060 Ti
       Ollama :11434      write SA Phase 6)   ComfyUI / CUDA
       LLM + embeddings   Prometheus          GPU exporters
                          CNPG Postgres
                          + pgvector

       infra-node-01 (NOT in k3s): AdGuard DNS, Vikunja, Uptime Kuma


                         📱 ANDROID PHONE
                         ┌────────────────┐
                         │ EdgeNest App   │
                         │ LiteRT edge LLM│
                         │ local memory   │
                         │ offline queue  │
                         │ (voice later)  │
                         └────────────────┘
```

---

## 5. Component Responsibilities

| Component | Where | Responsibility |
|---|---|---|
| 📱 Phone | Android | Edge inference, local-vs-remote decision, UI, offline operation, (later) voice |
| ☁️ EdgeNest Relay | GCP Cloud Run | Device auth, rate limiting, forwarding/streaming, metadata-only logging. **No** agent logic, **no** tool access, **no** stored conversation content |
| 🔐 Private link | Cloudflare Tunnel + Access | Authenticated path from Cloud Run into the homelab without opening inbound ports |
| 🧠 EdgeNest Agent | k3s on `control-plane-01` | Remote-tier routing, agent runtime, Tool Gateway, sessions, memory, telemetry |
| 🍎 Mac mini M6 | macOS, outside k3s | Primary local LLM inference + embeddings (Ollama) |
| ☸️ k3s | `control-plane-01`, `gpu-node-01` | Infrastructure orchestration, hosts the Agent, Postgres, monitoring |
| 🖥️ RTX 5060 Ti | `gpu-node-01` | GPU-intensive workloads (ComfyUI, CUDA, PyTorch) |
| 🗄️ Postgres (CNPG) | k3s | Sessions, audit log, request telemetry, pgvector RAG store |
| 📈 Prometheus/Grafana | k3s | Metrics source for tools; EdgeNest dashboard |
| ☁️ Cloud LLM | External API | Optional high-end reasoning, policy-gated |

---

## 6. Phone Application

### Technology
- Android, Kotlin, Jetpack Compose
- LiteRT with a local quantized LLM
- Local speech-to-text / text-to-speech (post-MVP, Phase 7)

### Phone responsibilities
1. Accept user input (text in MVP; voice later).
2. Perform basic local inference.
3. **Decide local vs. remote** (the phone's only routing decision — §9).
4. Execute simple offline tasks.
5. Connect securely to the EdgeNest API.
6. Display streaming responses, labeled with execution location.
7. Maintain limited local memory and an offline question queue.

---

## 7. Edge Model

A **small 1–4B parameter model**, 4-bit quantized, chosen for low memory footprint, fast inference, instruction following, and intent classification. Specific model selected during Phase 2 based on what LiteRT supports well on the target device at that time.

The edge model is not the primary reasoning model. Its jobs:

```text
UNDERSTAND → CLASSIFY → (ANSWER LOCALLY | HAND OFF) → SUMMARIZE
```

---

## 8. EdgeNest API: Relay + Agent

The phone talks to **one API**. That API is implemented in two halves:

### 8.1 Relay (GCP Cloud Run)
- authenticate devices (device token, §17)
- rate limit
- forward requests and stream responses to/from the Agent
- log request metadata only (request_id, device_id, timestamps, status, latency) — never message content
- hold no tool credentials, no kubeconfig, no Ollama access

### 8.2 Agent (homelab, k3s)
- manage sessions (Postgres)
- route among homelab and cloud tiers (§9)
- run the agent loop
- enforce tool policy via the Tool Gateway (§14)
- call Ollama on the Mac mini
- call k3s / Prometheus / GPU services through tools
- optionally call a cloud LLM (policy-gated)
- write telemetry and audit records (Postgres)

The Agent accepts requests **only** from the Cloudflare tunnel with a valid Access service token, plus LAN access for development.

**Relationship to ADR 0022:** the Homelab Ops Agent planned in ADR 0022 (RAG + multi-agent) *is* the EdgeNest Agent's homelab layer. ADR 0022 should be updated to say it is delivered through EdgeNest rather than as a separate product. ADR 0023 (Dev Agent Swarm) remains separate.

---

## 9. Request Routing

Routing is decided in exactly two places, each owning one question:

| Decision | Owner | Question |
|---|---|---|
| Local vs. remote | Phone (edge model) | "Can I answer this on-device?" |
| Which remote tier | Agent (homelab) | "Homelab (Mac mini / tools / GPU) or cloud LLM?" |

The phone attaches its classification to remote requests as a hint; the Agent makes the final remote-tier decision.

```json
{
  "message": "Why is my GPU node unhealthy?",
  "hint": {
    "complexity": "medium",
    "requires_tools": true,
    "privacy": "high"
  }
}
```

```text
Phone: can edge model answer?
 ├── YES → answer on phone            [label: Local]
 └── NO  → EdgeNest API
            │
            Agent: can homelab handle it?
             ├── YES → Mac mini / tools / GPU   [label: Homelab]
             └── NO  → privacy allows cloud?
                        ├── YES → cloud LLM      [label: Cloud]
                        └── NO  → explain why it can't be answered
```

---

## 10. Routing Policy

### Tier 0 — Phone (LiteRT)
Basic questions, simple classification, short summaries, offline commands, local preferences, simple conversation.

### Tier 1 — Mac mini (Ollama)
Reasoning, RAG, homelab analysis, tool calling, code analysis, troubleshooting, larger context.

### Tier 2 — RTX node
Image/video generation, CUDA, PyTorch, specialized ML. Invoked via tools/APIs, not as a general chat model.

### Tier 3 — Cloud LLM
Very complex reasoning, very large context, web research, unavailable capabilities, explicit user request.

### 10.1 Privacy and fallback rules
- Requests carry a privacy level: `high` (default for anything touching homelab data or personal memory) or `normal`.
- **High-privacy requests never fall back to cloud.** If the homelab tier is unavailable (e.g. Mac mini down), the Agent returns a clear "homelab unavailable" response rather than silently using a cloud model.
- Normal-privacy requests may fall back to cloud; the response is labeled `Cloud`.
- An explicit user request ("ask Claude…") overrides tier choice but not the high-privacy data rule: homelab data is not attached to cloud requests without explicit per-request confirmation.

---

## 11. Mac Mini M6

The Mac mini is the **primary local AI inference appliance**: native macOS Ollama, outside k3s (ADR 0024). As built: Apple M6, 32GB unified memory, 512GB SSD, 2.5GbE wired, Ollama as a system LaunchDaemon on `0.0.0.0:11434` (`infra/mac-mini/`).

### 11.1 Realistic model plan
32GB of unified memory is shared with macOS, and by default macOS lets the GPU wire only a portion of it (roughly two-thirds; adjustable). Plan for **one primary reasoning model plus one embedding model resident at a time**, not three size tiers:

| Role | Candidate | Notes |
|---|---|---|
| Primary reasoning + tool calling | `qwen2.5:14b` (Q4) | Already pulled; measured ~20 tok/s on this box |
| Embeddings | small embedding model (e.g. `nomic-embed-text`) | Few hundred MB; stays resident alongside |
| Fast/light (optional) | 3–4B instruct model | Only if routing/summarization latency needs it |

Models ≥30B are out of scope for this box at 32GB if they must coexist with anything else. Final choices are validated in Phase 1 against real latency and tool-calling reliability.

### 11.2 Ollama consolidation (target state — pending ADR, §33 D1)
Target: **the Mac mini is the only Ollama host**, and `gpu-node-01`'s GPU is dedicated to ComfyUI/CUDA work. This ends the manual Ollama↔ComfyUI replica toggle on the single RTX.

This supersedes part of ADR 0024 (which kept two Ollama hosts) and requires migrating current consumers of `gpu-node-01`'s Ollama:
- Open WebUI (`ollama` namespace)
- n8n AI Agent workflow (`hybrid-local-claude-agent.json`, uses `qwen2.5:14b`)
- Telegram bot workflow

Until migrated, both hosts run. Consolidation is a parallel track (§28, T1): not an MVP blocker, but a prerequisite for Phase 3 (creative jobs).

---

## 12. k3s Integration

```text
k3s
├── control-plane-01  — control plane, EdgeNest Agent, Postgres, monitoring, apps
└── gpu-node-01       — GPU worker (ComfyUI; Ollama until consolidation)

Outside k3s (by design, ADR 0013/0024):
├── infra-node-01     — AdGuard DNS, Vikunja, Uptime Kuma
└── Mac mini M6       — Ollama
```

The Agent interacts with Kubernetes only through Tool Gateway tools backed by a **dedicated read-only ServiceAccount** (get/list/watch on nodes, pods, deployments, events, pod logs). Write-capable tools (Phase 6) use a **separate** ServiceAccount with narrowly scoped verbs.

```text
get_cluster_status()  get_nodes()  get_pods()
get_deployment()      get_logs()   get_events()
```

---

## 13. GPU Integration

The RTX 5060 Ti remains a specialized GPU worker: ComfyUI, CUDA, PyTorch, image/video generation, GPU diagnostics.

GPU health tools reuse what already exists:
- `nvidia-gpu-exporter` / Prometheus (ADR 0017)
- `gpu-temp-exporter` on `:9400` (`infra/gpu-node-01/gpu-temp-exporter/`)

The Agent can submit ComfyUI jobs via its API without exposing the GPU node to the phone. After Ollama consolidation (§11.2) ComfyUI stays scheduled permanently; until then, job submission must check that ComfyUI is scheduled (not scaled to 0) and report clearly if it isn't.

### 13.1 Creative jobs (Phase 3)

> "Generate a cyberpunk visualization of my homelab." / "Turn this photo into a 5-second video."

```text
📱 Phone ──submit──▶ Relay ──▶ Agent: validate → queue → job_id ──▶ 📱 (immediate)
                                  │
                                  ▼ (when GPU free + temp OK)
                             ComfyUI API (gpu-node-01, LAN only)
                                  │
                                  ▼
                             result stored in homelab
                                  │
📱 ◀── notification ◀── Agent: job done, short-lived download URL
📱 ──fetch──▶ Relay/Tunnel ──▶ Agent ──▶ file
```

Requirements:
- **Asynchronous.** Image jobs take seconds, video jobs many minutes; no request holds a connection open for the job's duration. Submit returns a `job_id` immediately; the phone polls or is notified.
- **Fixed workflow templates.** Each job type maps to a versioned ComfyUI workflow in the repo (initially: text→image with `z_image_turbo`; image→video with the Wan2.2 Q4_K_M GGUF dual-model workflow). The model only fills typed parameters (prompt, negative prompt, size, steps, duration, input image) — it never constructs or edits raw workflow graphs.
- **Bounded parameters.** Templates declare limits (max resolution, max frames/duration, max steps) so a request can't push the node into the memory conditions behind ADR 0018's crashes.
- **One GPU job at a time.** The Agent's queue (Postgres-backed, survives Agent restarts) runs jobs serially, FIFO.
- **Health pre-check.** Before dispatch, the Agent checks GPU temperature and node readiness via existing exporters; if unhealthy, the job waits and the phone is told why.
- **Result delivery.** Outputs are stored in the homelab (PVC) and fetched via short-lived signed URLs through the same Relay/Tunnel path, in a separate download request — not embedded in the chat stream. Results are retained for a bounded period (e.g. 7 days) unless saved on the phone.
- **Input uploads** (image→video) go through the same path with a size cap.
- **Cancellation:** queued jobs can be cancelled; running jobs are interrupted via ComfyUI's API.

---

## 14. Tool Gateway

A **mandatory security boundary**, running inside the Agent in the homelab.

The LLM never receives `ssh`, `kubectl`, `docker`, `rm`, `sudo`, or any generic command execution. It receives structured tools with declared risk:

```json
{
  "name": "get_gpu_status",
  "description": "Return GPU utilization, temperature and VRAM",
  "risk": "READ_ONLY"
}
```

Every tool call is written to an audit log (Postgres): request_id, tool, arguments, result status, who/what approved it.

### 14.1 Prompt-injection posture
Tool results — especially logs, events, and RAG documents — can contain attacker- or app-controlled text. Therefore:
- tool output is passed to the model as data, clearly delimited;
- **no write action executes without explicit user confirmation on the phone**, regardless of what the model or tool output says;
- confirmations show the exact action and target, generated by the Tool Gateway, not by the model's free text.

---

## 15. Tool Categories

### Read-only — automatically allowed
```text
get_gpu_status      get_node_status     get_pod_status
get_logs            get_cluster_health  get_disk_usage
get_memory_usage    get_ollama_status
```

### Jobs — user-initiated, confirm card (Phase 3)
```text
submit_image_job    submit_video_job    get_job_status    cancel_job
```
Consume GPU time but change no infrastructure state. The phone shows a confirm card (template, parameters, estimated duration, queue position) generated by the Tool Gateway before the job is queued — so a model can't silently queue GPU work from injected text.

### Actions — always require user confirmation (Phase 6+)
```text
restart_application     (rollout restart of an allow-listed Deployment)
scale_application       (allow-listed Deployments, bounded replicas — e.g. Ollama/ComfyUI toggle)
refresh_service
```

### Out of scope — not offered as tools
```text
delete_pod  delete_pvc  restart_node  scale_cluster
modify_network  execute_shell
```
These are deliberately not exposed even with confirmation; they remain manual operations over SSH from a jump box. Revisit individually with an ADR if a concrete need arises.

v1.0's "low-risk actions potentially automatically executable" category is removed (see §14.1). Auto-execution may be revisited after Phase 6 audit data exists.

---

## 16. Security Architecture

```text
📱 Phone
   │ HTTPS + device token
   ▼
☁️ Cloud Run Relay  (no homelab credentials except the Access service token)
   │ HTTPS + Cloudflare Access service token
   ▼
🔐 Cloudflare Tunnel  (outbound-only from homelab, dedicated hostname)
   │
   ▼
🧠 EdgeNest Agent (k3s)
   ├── Mac mini Ollama  (LAN only)
   ├── k3s API          (read-only SA)
   └── GPU services     (LAN only)
```

Never exposed to the public Internet: `11434` Ollama, `6443` Kubernetes, `22` SSH, ComfyUI, Prometheus, Postgres `30432`. None of these are routed through the tunnel; only the Agent's API hostname is.

The tunnel hostname is protected by Cloudflare Access (service-token policy) so that only the Relay can reach it — the Agent additionally verifies the Access JWT. This follows the same named-tunnel pattern as ADR 0019, not the auto-generated-tunnel pattern from the ADR 0012 incident.

---

## 17. Authentication

### Initial (MVP)
- TLS everywhere on the public path
- Device registration producing a per-device token, stored in Android Keystore
- Relay validates device token; Relay ↔ Agent authenticated by Cloudflare Access service token
- Device revocation (delete token) from day one — single user, but a lost phone must be cut off

### Future
- Passkeys / biometric confirmation for Phase 6 actions
- Short-lived tokens
- Multiple devices

---

## 18. Memory

| Layer | Where | Contents |
|---|---|---|
| Phone (short-term) | On device | Recent conversations, preferences, offline info, queued questions |
| Homelab (persistent) | CNPG Postgres + pgvector | Sessions, conversation history, audit log, telemetry, RAG corpus |
| Cloud | — | **No persistent personal memory.** Relay stores metadata only. |

pgvector must be available in the CNPG Postgres image before Phase 4 — verify, and if absent, decide between a pgvector-enabled image or a separate instance.

---

## 19. RAG

EdgeNest should understand the homelab. Initial sources:

```text
homelab GitHub repository: CLAUDE.md, READMEs, docs/decisions (ADRs),
docs/hardware, Kubernetes manifests (infra/k8s/), runbooks
```

> "How did I configure my GPU node?"

The Agent retrieves relevant documents and cites them rather than inventing an answer. Embeddings are generated on the Mac mini; vectors stored in pgvector. Ingestion re-runs on repo changes. Retrieved content is treated as data per P7.

---

## 20. Voice Interface (Phase 7, post-MVP)

```text
Voice → Local STT → LiteRT → EdgeNest API → Agent → Tool/LLM → Response → Local TTS
```

Common commands should work offline when possible.

---

## 21. Offline Mode

```text
📱 (no Internet)
 │
 ▼
LiteRT
 ├── answer locally
 └── queue question
```

When connectivity returns, queued **questions** are sent and answered.

**Actions are never queued for automatic replay.** If the user asks for an action while offline, the app records it as a reminder; on reconnect it is re-presented with current state and requires fresh confirmation ("You asked to restart Ollama 3 hours ago; it is currently healthy. Still restart?").

Every response is labeled: **Offline / Local / Homelab / Cloud**.

---

## 22. Cloud Infrastructure

### Initial deployment
**Google Cloud Run** hosting the stateless Relay only.

```text
GCP
├── Cloud Run: EdgeNest Relay
├── Secret Manager: Access service token, device-token signing key
└── Cloud Logging: metadata-only request logs
```

Not needed: GKE, Cloud SQL, Redis, GPU instances, **GCP Cloud VPN / HA VPN** (per-tunnel hourly pricing alone exceeds the cost target — rejected in favor of Cloudflare Tunnel).

### Why GCP at all
A phone on a mesh VPN (e.g. Tailscale) could reach a homelab-hosted API directly with no cloud component. GCP is kept deliberately because it provides: a stable, managed public HTTPS endpoint the phone can always reach without a VPN client; an isolation layer where device auth and rate limiting happen before anything touches the homelab; a natural place for cloud-LLM API key custody in later phases; and portfolio value demonstrating hybrid edge/cloud/on-prem architecture. If these stop justifying it, the Relay can be replaced without changing the Agent.

---

## 23. Target Cloud Cost

| Component | Target |
|---|---:|
| Cloud Run (Relay, scale-to-zero) | $0–$2 |
| Network egress | $0–$2 |
| Cloud Logging (metadata only) | <$1 |
| Secret Manager | ~$0 |
| Cloudflare Tunnel + Access | $0 (free tier) |
| **Target total** | **<$5/month** |

Excludes external LLM API usage. Cold starts on scale-to-zero are accepted for MVP; revisit `min-instances=1` only if latency demands it and cost allows.

---

## 24. Observability

Every request produces a record (Agent → Postgres; Relay logs only its metadata subset):

```text
request_id  device_id  timestamp  routing_decision  location_label
model  latency_ms  tokens_in/out  tool_calls  success  error  cloud_cost
```

The dashboard is a **Grafana** dashboard on the existing Prometheus/Grafana stack (ADR 0017), reading from Postgres and Prometheus:

```text
EDGENEST
────────────────────────────
Requests today       143
  Phone (local)       91
  Homelab             43
  Cloud                9
Avg latency         1.8s
Offline (queued)      14
Cloud AI cost      $0.38
```

Phone-local requests are counted when the phone next syncs (count + latency only).

---

## 25. Model Routing Metrics

Measured per tier and model: **performance** (latency, tok/s, success rate), **cost** (local vs. cloud, API cost), **energy** (phone battery, compute utilization), **quality** (user thumbs up/down, tool success, answer correctness on a small eval set). Eventually routing optimizes on these (Phase 8).

---

## 26. API

```http
POST /v1/chat            (streaming)
POST /v1/devices/register
POST /v1/actions/{id}/confirm     (Phase 6)
GET  /v1/health

POST   /v1/jobs                   (Phase 3: submit; returns job_id)
GET    /v1/jobs/{id}              (status, queue position, progress)
GET    /v1/jobs/{id}/result       (302 → short-lived signed URL)
DELETE /v1/jobs/{id}              (cancel)
POST   /v1/uploads                (input image for image→video, size-capped)
```

```json
{
  "message": "Is my GPU node healthy?",
  "conversation_id": "abc123",
  "hint": { "complexity": "medium", "requires_tools": true, "privacy": "high" }
}
```

```json
{
  "response": "Your GPU node is healthy...",
  "execution": {
    "location": "homelab",
    "model": "qwen2.5:14b",
    "tools_used": ["get_node_status", "get_gpu_status"]
  }
}
```

---

## 27. Repository Layout

EdgeNest lives in the existing homelab repo, alongside — not replacing — the current structure:

```text
homelab/
├── edge-ai/                    # NEW
│   ├── android/                # app, inference, networking (voice later)
│   ├── relay/                  # Cloud Run service
│   ├── agent/                  # EdgeNest Agent: router, agent, tools, auth, memory
│   ├── models/                 # edge model notes, Ollama Modelfiles
│   ├── rag/                    # ingestion
│   └── docs/
├── infra/
│   ├── k8s/base/edgenest/      # NEW: Agent Deployment, ServiceAccounts/RBAC, tunnel route
│   ├── k8s/base/...            # existing (ollama-openwebui, comfyui, n8n, postgres, ...)
│   ├── mac-mini/               # existing: Ollama LaunchDaemon, power, SSH
│   ├── gpu-node-01/  infra-node-01/  bootstrap/  jumpbox/
├── agents/                     # existing (nlp-to-sql, shared)
├── docs/
│   ├── decisions/              # ADRs
│   ├── hardware/
│   └── product/edgenest-prd.md # this document
└── CLAUDE.md
```

---

## 28. Development Phases

### Phase 0 — Connectivity
**Build:** GCP project; Cloud Run Relay (hello-world + device token check); dedicated Cloudflare Tunnel hostname with Access service-token policy; Agent stub in k3s that forwards a prompt to Mac mini Ollama; health checks.

**Success:**
```text
curl (internet, valid token) → Cloud Run → Tunnel → Agent → Mac mini Ollama → answer
```
plus: request without device token rejected at Relay; request to tunnel hostname without Access token rejected by Cloudflare; `11434` not reachable from the Internet.

### Phase 1 — Homelab Agent (read-only)
**Build:** agent loop on Mac mini model; Tool Gateway with read-only ServiceAccount; first tools `get_node_status`, `get_gpu_status` (Prometheus/exporters); sessions + telemetry + audit in Postgres; streaming.

**Success:** "What's wrong with my GPU node?" (via curl) returns an evidence-based answer citing tool output.

### Phase 2 — Android app + Edge AI
**Build:** Compose chat UI (text); LiteRT edge model; local-vs-remote decision; device registration; response location labels; offline answers + question queue.

**Success:** user chats offline on the phone, and the same app seamlessly hands off homelab questions to the Agent.

### ✅ MVP = Phases 0–2 (see §29)

### Track T1 — Ollama consolidation (§11.2) — prerequisite for Phase 3
Migrate Open WebUI, n8n, Telegram bot to Mac mini Ollama; remove Ollama from `gpu-node-01`; dedicate GPU to ComfyUI. Requires ADR (§33 D1). Not an MVP blocker — can run in parallel with Phases 0–2 — but **must be complete before Phase 3**, since creative jobs need ComfyUI permanently scheduled on the GPU.

### Phase 3 — Creative jobs (GPU)
**Build:** async job API (§26); job queue in the Agent (Postgres-backed, GPU concurrency 1); ComfyUI client with fixed workflow templates (§13.1); GPU-temperature pre-check; result storage + short-lived signed download URLs; phone UI for submit/progress/gallery; completion notification.

**Success:** from the phone, "generate an image of my homelab as a cyberpunk city" returns an image, and an image→video request completes in the background and notifies the phone when ready — with no ComfyUI port exposed and no manual scale toggle.

### Phase 4 — RAG
pgvector (verify availability), repo ingestion, embeddings on Mac mini, cited retrieval. Delivers ADR 0022's RAG scope.

### Phase 5 — More tools + Grafana dashboard
Remaining read-only tools (§15), EdgeNest Grafana dashboard, routing metrics collection.

### Phase 6 — Agentic actions
Write ServiceAccount, confirmation flow on phone, allow-listed actions, multi-step workflows (confirm → act → verify → report), audit review.

> "Restart Ollama." → "Ollama is healthy but not answering requests. Restart it?" → **Confirm → restart → verify → report.**

### Phase 7 — Voice
Local STT/TTS, interaction flow. "Hey EdgeNest, how is my homelab?"

### Phase 8 — Intelligent routing
Optimize on quality, latency, battery, privacy, cost, availability using Phase 5 metrics.

---

## 29. MVP Definition of Done

The user picks up their phone and **types**:

> **"Is my GPU node healthy?"**

```text
📱 Text input
   ↓
LiteRT: classify → needs homelab
   ↓
☁️ Cloud Run Relay (device auth)
   ↓
🔐 Cloudflare Tunnel + Access
   ↓
🧠 EdgeNest Agent (k3s)
   ├─→ get_node_status (k3s API, read-only SA)
   └─→ get_gpu_status  (Prometheus / exporters on gpu-node-01)
   ↓
🍎 Mac mini Ollama: reason over tool results
   ↓
☁️ Relay (stream)
   ↓
📱 Answer, labeled "Homelab", tools listed
```

And: a simple question ("what's 15% of 80?") is answered on-device, labeled **Local**, with no network call.

Acceptance:
- No public SSH, Ollama, Kubernetes API, or other homelab port.
- No manual model or server selection.
- No write actions available.
- Request appears in Postgres telemetry with routing decision and latency.
- Revoking the device token immediately blocks the phone.

Voice is **not** part of the MVP (Phase 7).

---

## 30. Future Vision

- **Proactive AI:** "Your GPU node is running hot." (builds on existing Uptime Kuma / exporters)
- **Assisted troubleshooting:** "Ollama stopped answering. Restart it?" — confirmation-gated; autonomy only after audit history justifies it
- **Home automation:** "Turn off the office lights."
- **Developer agent:** "Review my latest GitHub PR." (ADR 0023 territory)
- **Personal knowledge:** "What did I decide about my NAS architecture?"
- **GPU workload scheduling:** "Queue this video generation for when the GPU is idle."
- **Multi-device:** phone, MacBook, Mac mini, homelab, cloud as one system.

---

## 31. Product North Star

> **You have one AI assistant. It doesn't matter whether its intelligence is currently running on your phone, your Mac mini, your GPU server, or the cloud.**

The system continuously chooses the best execution location based on **privacy + latency + capability + cost + availability** — and always tells you where it ran.

**📱 Edge → ☁️ GCP relay → 🧠 Homelab agent → 🍎 M6/Ollama · 🖥️ RTX/k3s.**

---

## 32. Non-Goals (v1.1)

- Joining the Mac mini to k3s (ADR 0024)
- Multi-user support
- Generic shell / SSH / kubectl access for the model
- Autonomous (unconfirmed) write actions
- Hosting large (≥30B) models locally
- iOS client

---

## 33. Decisions Requiring ADRs

| ID | Decision | Proposed | Needed before |
|---|---|---|---|
| D1 | Ollama consolidation onto the Mac mini (partially supersedes ADR 0024) | Mac mini sole Ollama host; GPU dedicated to ComfyUI | Track T1 (gates Phase 3) |
| D2 | Placement of agent runtime + Tool Gateway | Homelab k3s; Cloud Run is a stateless relay | Phase 0 |
| D3 | Cloud ↔ homelab private link | Cloudflare Tunnel + Access service token (reject GCP Cloud VPN on cost; Tailscale userspace as fallback) | Phase 0 |

Also update ADR 0022 to state it is delivered as EdgeNest's homelab layer (§8.2).

## 34. Open Questions

- Edge model choice for LiteRT on the target phone (Phase 2).
- Primary reasoning model: does `qwen2.5:14b` tool-call reliably enough, or is another ~14B model better on the Mac mini? (Phase 1 eval)
- pgvector availability in the current CNPG image (Phase 4).
- Cloud LLM provider/key custody: Relay (GCP Secret Manager) vs. Agent (homelab) — leaning Agent, so cloud calls are policy-checked in one place.
- Mac mini single point of failure: is "homelab unavailable" acceptable for high-privacy requests, or should `gpu-node-01` keep a fallback Ollama after consolidation?
