# ollama-openwebui/

Ollama (GPU-scheduled model server, `gpu-node-01`) + Open WebUI (browser UI, `control-plane-01`), both in the `ollama` namespace. See [ADR 0008](../../../../docs/decisions/0008-nvidia-device-plugin-default-runtime.md) for GPU scheduling and [ADR 0009](../../../../docs/decisions/0009-nodeport-then-traefik-ingress.md) for why these are exposed via `NodePort` rather than Ingress right now.

## Apply

```bash
sudo k3s kubectl apply -f infra/k8s/base/ollama-openwebui/00-namespace.yaml
sudo k3s kubectl apply -f infra/k8s/base/ollama-openwebui/01-ollama.yaml
sudo k3s kubectl apply -f infra/k8s/base/ollama-openwebui/02-open-webui.yaml
```

## Access from the LAN (e.g. the Dell G5)

- Open WebUI: `http://<any-node-ip>:30080` (e.g. `http://192.168.0.106:30080`) — sign up on first visit, the first account becomes admin.
- Ollama API directly: `http://<any-node-ip>:31434` (e.g. `http://192.168.0.79:31434`) — e.g. `curl http://192.168.0.79:31434/api/tags`.

NodePort Services are reachable via **any** node's IP regardless of which node the pod actually runs on — kube-proxy routes it internally.

## Pulling a model

No models are pre-pulled. Either:
- In Open WebUI: use the model pull UI (Settings → Models), or
- Directly: `sudo k3s kubectl exec -n ollama deploy/ollama -- ollama pull <model>` (e.g. `llama3.2`)

## Verify GPU is actually being used

```bash
sudo k3s kubectl exec -n ollama deploy/ollama -- nvidia-smi
```

Should show the RTX 5060 Ti; check GPU-Util climbs during an actual generation request.
