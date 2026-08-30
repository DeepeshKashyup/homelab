# n8n/

Workflow automation, in the `n8n` namespace, pinned to `control-plane-01` (no GPU needed, same reasoning as Open WebUI/Postgres/Plex). First real consumer of the shared Postgres cluster ([`infra/k8s/base/postgres/`](../postgres/)) beyond its own bootstrap database. Backlog #16 — #17 (a hybrid local Ollama + Claude reasoning workflow) and #18 (a Telegram bot) build on this once it's up.

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

Ollama's internal Service is reachable in-cluster at `http://ollama.ollama.svc.cluster.local:11434` — no NodePort hop needed since both run in the same k3s cluster. In n8n, an **HTTP Request** node (or the community Ollama node, if installed) pointed at that URL is enough for backlog #17's hybrid local-model + Claude workflow. Remember Ollama needs to actually be scaled up (`replicas: 1`) and ComfyUI scaled down first — see [`../ollama-openwebui/README.md`](../ollama-openwebui/) for the toggle, since both still contend for `gpu-node-01`'s single GPU.

## First-deploy verification checklist

- `kubectl get database,databaserole -n postgres n8n` shows both reconciled successfully (check `kubectl describe` if not — CNPG surfaces role/DB creation errors there).
- n8n's first-run wizard completes and the owner account persists across a pod restart (`kubectl rollout restart deployment/n8n -n n8n`) — confirms it's actually reading/writing Postgres, not silently falling back to SQLite.
- A test workflow with an HTTP Request node to `http://ollama.ollama.svc.cluster.local:11434/api/tags` returns n8n's model list — confirms in-cluster connectivity to Ollama.

Update this README once verified — note here if the CNPG `DatabaseRole`/`Database` CRDs needed different fields (they're a newer, actively-evolving part of the operator).
