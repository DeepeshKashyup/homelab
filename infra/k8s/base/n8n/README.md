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

## Backlog #17: hybrid local + Claude triage workflow

[`workflows/hybrid-local-claude-triage.json`](workflows/hybrid-local-claude-triage.json) is a small router workflow validating the hybrid-reasoning pattern: a cheap local model (`gemma3:4b` via Ollama) triages each question first and answers directly if it's confident; anything it flags as uncertain escalates to the Claude API for the real answer. Plain **HTTP Request** nodes are used throughout rather than n8n's bundled LangChain/AI-Agent nodes — those node types move fast across n8n versions and are riskier to hand-author blind outside the UI.

**Import it:**

1. In n8n, **Workflows → Import from File**, pick this JSON.
2. Open the **Ask Claude (Escalation)** node and assign an Anthropic API credential (create one under **Credentials** with an API key from `console.anthropic.com` — not included in the JSON, never checked into git).
3. Click **Set Question**, edit the `question` value, then **Execute workflow** from the trigger. Try one simple factual question (should stay local) and one that needs current information or careful judgment (should escalate) to see both paths.
4. Inspect the **Final Result** node's output — `source` says which model actually answered, `reason` says why the router decided that.

## First-deploy verification checklist

- [x] `kubectl get database,databaserole -n postgres n8n` shows both reconciled successfully (check `kubectl describe` if not — CNPG surfaces role/DB creation errors there). — confirmed 2026-08-29.
- [x] n8n's first-run wizard completes and the owner account persists across a pod restart (`kubectl rollout restart deployment/n8n -n n8n`) — confirms it's actually reading/writing Postgres, not silently falling back to SQLite. — confirmed 2026-08-29 (30+ migrations ran against the `n8n` database on first boot).
- [x] In-cluster connectivity to Ollama confirmed (see above).
- [x] Backlog #17's hybrid workflow imported, an Anthropic credential assigned, and both the local-answer and Claude-escalation paths actually exercised at least once. — confirmed 2026-08-29.

**Known minor follow-up, not blocking:** n8n logged a deprecation warning on startup that `WEBHOOK_URL` (used in `02-n8n.yaml`) should become `N8N_WEBHOOK_URL` in a future n8n version — update the manifest whenever that becomes a hard requirement rather than just a warning.
