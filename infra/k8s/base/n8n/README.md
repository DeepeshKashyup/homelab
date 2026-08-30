# n8n/

Workflow automation, in the `n8n` namespace, pinned to `control-plane-01` (no GPU needed, same reasoning as Open WebUI/Postgres/Plex). First real consumer of the shared Postgres cluster ([`infra/k8s/base/postgres/`](../postgres/)) beyond its own bootstrap database. Backlog #16 — **done and verified 2026-08-29**: migrations ran clean against the dedicated `n8n` Postgres database, UI/`/healthz` reachable at `http://192.168.0.47:30678`, and the pod confirmed reaching Ollama's internal Service directly. #17 (a hybrid local Ollama + Claude reasoning workflow, see below) and #18 (a Telegram bot) build on this.

## Apply

Two Secrets need to exist **before** applying the manifests — neither is checked in (same practice as Plex's `PLEX_CLAIM` and CNPG's own auto-generated credentials):

```bash
# 1. DB password for n8n's dedicated Postgres role — needed in TWO namespaces,
#    same password both places (Secrets don't cross namespaces).
PASS=$(openssl rand -base64 24)
kubectl create secret generic n8n-db-owner -n postgres \
  --type=kubernetes.io/basic-auth \
  --from-literal=username=n8n --from-literal=password="$PASS"
kubectl create secret generic n8n-db-credentials -n n8n \
  --from-literal=username=n8n --from-literal=password="$PASS"

# 2. n8n's own credential-encryption key. Losing this makes every stored
#    credential in n8n's workflows undecryptable -- back it up somewhere
#    outside the cluster once generated (a password manager entry is fine).
kubectl create secret generic n8n-encryption-key -n n8n \
  --from-literal=N8N_ENCRYPTION_KEY="$(openssl rand -hex 24)"
```

Then:

```bash
kubectl apply -f infra/k8s/base/n8n/00-namespace.yaml
kubectl apply -f infra/k8s/base/n8n/01-postgres-role-db.yaml
kubectl apply -f infra/k8s/base/n8n/02-n8n.yaml
```

Wait for it to come up:

```bash
kubectl get database,databaserole -n postgres n8n   # both should show a "ready"/reconciled status
kubectl get pods -n n8n -w
```

No firewall change needed — `30678` already falls inside the NodePort range opened by [`infra/k8s/open-nodeport-firewall.sh`](../../open-nodeport-firewall.sh).

## First-run setup

From a browser on the LAN, go to `http://192.168.0.47:30678`. n8n's first-run wizard creates the owner account (stored in the `n8n` Postgres database, not baked into any manifest).

## Connecting to Ollama

Ollama's internal Service is reachable in-cluster at `http://ollama.ollama.svc.cluster.local:11434` — no NodePort hop needed since both run in the same k3s cluster. Confirmed working via `kubectl exec -n n8n deploy/n8n -- wget -qO- http://ollama.ollama.svc.cluster.local:11434/api/tags`, which returned all 5 loaded models. Remember Ollama needs to actually be scaled up (`replicas: 1`) and ComfyUI scaled down first — see [`../ollama-openwebui/README.md`](../ollama-openwebui/) for the toggle, since both still contend for `gpu-node-01`'s single GPU.

## Backlog #17: hybrid local + Claude workflow

**v1 (superseded), [`workflows/hybrid-local-claude-triage.json`](workflows/hybrid-local-claude-triage.json):** a hardcoded `IF` node routes to Claude based on a confidence flag the local model outputs. Functional, but on reflection this is a conditional pipeline, not actually an agent — the model doesn't choose to call Claude, my `IF` node does, based on a field the model happened to output. Kept in the repo for reference/comparison, no longer the recommended import.

**v2 (current), [`workflows/hybrid-local-claude-agent.json`](workflows/hybrid-local-claude-agent.json):** a real agent using n8n's native LangChain **AI Agent** node. `qwen2.5:14b` (via Ollama, one of the 5 local models with tool-calling capability) is the agent's own reasoning model, with Claude wired in as a callable **tool** (`@n8n/n8n-nodes-langchain.toolHttpRequest`) rather than a hardcoded branch — the model itself decides, per request, whether to answer directly or invoke the tool. This is the thing backlog #17 actually asked for.

These are the most version-fragile node types in n8n (schemas move across releases) — confirmed present in this install (`n8n-nodes-langchain`'s `Agent`, `LmChatOllama`, `ToolHttpRequest` node files all exist), but if any of the three shows as an unrecognized/red node after import, delete just that node and re-add it fresh from the node panel (**AI → Agent / Chat Model / Tool**), then reconnect — the rest of the workflow is unaffected.

**Import it:**

1. In n8n, **Workflows → Import from File**, pick `hybrid-local-claude-agent.json`.
2. Open **Ollama Chat Model**, assign an Ollama API credential (`baseUrl: http://ollama.ollama.svc.cluster.local:11434`, no auth needed).
3. Open **Ask Claude**, assign an Anthropic API credential (same as v1 — `console.anthropic.com`, not checked into git).
4. Click **Set Question**, edit the `question` value, then **Execute workflow**. Try one simple factual question (agent should answer directly, no tool call) and one that needs current information or careful judgment (agent should decide on its own to call **Ask Claude**) to see both behaviors.
5. Inspect the **Final Result** node's `output` field, and check the **AI Agent** node's execution log/sub-run to see whether it actually invoked the tool and what it passed in — that's the agentic decision-making happening, not a hardcoded branch.

## Backlog #18: Telegram bot

n8n's Telegram integration is webhook-only (push), which meant the original "purely outbound polling bot" framing in the backlog description didn't hold once this got built — see [ADR 0019](../../../docs/decisions/0019-telegram-bot-webhook-cloudflare-tunnel.md) for the full story and why a named Cloudflare Tunnel ([`../cloudflared/`](../cloudflared/)) rather than a real port-forward was the answer. `N8N_WEBHOOK_URL` (`02-n8n.yaml`) points at `https://n8n-webhook.deepeshkumar.dev/`, the tunnel's public hostname.

[`workflows/telegram-ollama-bot.json`](workflows/telegram-ollama-bot.json): Telegram Trigger → check the sender's numeric Telegram user ID against Deepesh's own (hard-coded — a bot token alone is not access control, see ADR 0019) → if authorized, call Ollama and reply; if not, silently drop the message with no reply at all.

**Import it:**

1. In n8n, **Workflows → Import from File**, pick this JSON.
2. Open **Telegram Trigger**, assign a Telegram API credential (the bot token from `@BotFather` — not included in the JSON, never checked into git). Do the same on the **Reply on Telegram** node (same credential).
3. **Activate** the workflow (top-right toggle) — Telegram Trigger only registers its webhook with Telegram's `setWebhook` API once active, unlike the manual-trigger workflows above.
4. Message the bot from your own Telegram account — should get a real Ollama-generated reply.
5. Message the bot from a second account (or ask someone else to), or temporarily change the hard-coded ID to confirm it — should get silence, not a reply, confirming the access-control gate actually works.

## First-deploy verification checklist

- [x] `kubectl get database,databaserole -n postgres n8n` shows both reconciled successfully (check `kubectl describe` if not — CNPG surfaces role/DB creation errors there). — confirmed 2026-08-29.
- [x] n8n's first-run wizard completes and the owner account persists across a pod restart (`kubectl rollout restart deployment/n8n -n n8n`) — confirms it's actually reading/writing Postgres, not silently falling back to SQLite. — confirmed 2026-08-29 (30+ migrations ran against the `n8n` database on first boot).
- [x] In-cluster connectivity to Ollama confirmed (see above).
- [x] Backlog #17's hybrid workflow imported, an Anthropic credential assigned, and both the local-answer and Claude-escalation paths actually exercised at least once. — confirmed 2026-08-29 (v1); upgraded to a real AI Agent (v2) 2026-08-30, also confirmed working.
- [x] Backlog #18's Telegram workflow imported, activated, and exercised — confirmed 2026-08-30 (real reply received via the public webhook from Deepesh's own Telegram account).
- [x] `https://n8n-webhook.deepeshkumar.dev/` confirmed reachable from outside the LAN (see [`../cloudflared/README.md`](../cloudflared/README.md)) — confirmed 2026-08-30.
