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
- Directly: `sudo k3s kubectl exec -n ollama deploy/ollama -- ollama pull <model>` (e.g. `gemma3:4b`)

`gemma3:4b` (3.3GB) is a good first pull — fast, comfortably fits the RTX 5060 Ti's 16GB VRAM. `gemma3:12b` (8.1GB) also fits with room to spare if more capability is needed.

## Verify GPU is actually being used

```bash
sudo k3s kubectl exec -n ollama deploy/ollama -- nvidia-smi
```

Should show the RTX 5060 Ti; check GPU-Util climbs during an actual generation request.

## Gotcha: "model does not support tools"

Prompting a model that lacks tool/function-calling support (e.g. `gemma3:4b` — check a model's `capabilities` in `ollama list`/`/api/tags`; `["completion"]` means no tools) fails with `HTTP 400 ... does not support tools`, even with nothing obviously "tool"-related enabled in the chat. Cause: Open WebUI's per-model **Function Calling** setting defaults to (or gets set to) **Native**, which attaches a tools schema to every request for that model regardless of whether a tool is actually toggled on.

Fix: Admin Panel → Settings → Models (or Workspace → Models, depending on version) → select the model → set **Function Calling** to **Default** instead of **Native**. Models that do support tools (e.g. `llama3.1:8b`, `qwen2.5:14b`) aren't affected either way.
