# cloudflared/

A named Cloudflare Tunnel, in the `cloudflared` namespace, pinned to `control-plane-01`. Gives Telegram's webhook (backlog #18) a public HTTPS URL that reaches n8n, with **zero inbound exposure** on the home network — see [ADR 0019](../../../docs/decisions/0019-telegram-bot-webhook-cloudflare-tunnel.md) for the full reasoning, and why this is a deliberately different pattern from [ADR 0012](../../../docs/decisions/0012-comfyui-public-tunnel-security-incident.md)'s incident.

## One-time setup (done 2026-08-30, from the MacBook Pro jump box — not a cluster node)

This only needs redoing if the tunnel is ever deleted/recreated, or set up from a different machine:

```bash
brew install cloudflared          # one-off CLI, not the always-on tunnel (that runs in-cluster, see below)
cloudflared tunnel login          # opens a browser, authorize against the deepeshkumar.dev Cloudflare account
cloudflared tunnel create n8n-webhook
cloudflared tunnel route dns n8n-webhook n8n-webhook.deepeshkumar.dev
```

This writes a credentials JSON file under `~/.cloudflared/<tunnel-id>.json` on whichever machine ran it — that file is the actual secret (equivalent to a password) and must never be committed. It gets copied into the cluster as a Secret and isn't needed locally afterward:

```bash
# from the machine holding the credentials file:
cat ~/.cloudflared/<tunnel-id>.json | ssh control-plane-01 "cat > /tmp/tunnel-credentials.json"
ssh control-plane-01
  kubectl create secret generic cloudflared-credentials -n cloudflared \
    --from-file=credentials.json=/tmp/tunnel-credentials.json
  rm /tmp/tunnel-credentials.json
```

The tunnel ID itself (in `01-configmap.yaml`) is not sensitive — it's just an identifier, safe to commit, same as a resource name.

## Apply

```bash
kubectl apply -f infra/k8s/base/cloudflared/00-namespace.yaml
# create the cloudflared-credentials Secret first (above), then:
kubectl apply -f infra/k8s/base/cloudflared/01-configmap.yaml
kubectl apply -f infra/k8s/base/cloudflared/02-cloudflared.yaml
```

## Verify

```bash
kubectl get pods -n cloudflared -w
kubectl logs -n cloudflared deploy/cloudflared --tail=30   # should show "Registered tunnel connection" with no errors
curl -I https://n8n-webhook.deepeshkumar.dev/healthz        # from anywhere on the public internet, not just the LAN
```

A successful `/healthz` returning n8n's `{"status":"ok"}` from outside the home network confirms the whole chain: Cloudflare edge → tunnel → cloudflared pod → n8n Service.

## First-deploy verification checklist

- [x] `cloudflared` pod `Running`, logs show a registered tunnel connection with no errors. — confirmed 2026-08-30 (4 QUIC connections registered across Cloudflare edge locations).
- [x] `https://n8n-webhook.deepeshkumar.dev/healthz` reachable from outside the LAN. — confirmed 2026-08-30.
- [x] `N8N_WEBHOOK_URL` in `infra/k8s/base/n8n/02-n8n.yaml` updated to `https://n8n-webhook.deepeshkumar.dev/` so n8n registers the correct externally-reachable URL with Telegram's `setWebhook`. — confirmed 2026-08-30.
- [x] Telegram's webhook actually delivers a message to n8n end to end. — confirmed 2026-08-30 (real reply received via `workflows/telegram-ollama-bot.json`, see `infra/k8s/base/n8n/README.md`).
