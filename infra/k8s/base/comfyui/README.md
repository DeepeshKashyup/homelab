# comfyui/

ComfyUI (image generation, GPU-scheduled on `gpu-node-01`) in the `comfyui` namespace. Image: `ghcr.io/ai-dock/comfyui:latest-cuda`. See [ADR 0008](../../../../docs/decisions/0008-nvidia-device-plugin-default-runtime.md) for GPU scheduling and [ADR 0009](../../../../docs/decisions/0009-nodeport-then-traefik-ingress.md) for why this is exposed via `NodePort`.

## ⚠️ Read before applying: this image auto-exposes services publicly by default

`ai-dock/comfyui` is built for cloud GPU rental platforms and, unconfigured, auto-creates **public internet tunnels** (Cloudflare Quick Tunnels) for Jupyter, syncthing, SSH, and a service portal — with a default password of literally `"password"`. This actually happened on first deploy here; see [ADR 0012](../../../../docs/decisions/0012-comfyui-public-tunnel-security-incident.md) for the full incident. `01-comfyui.yaml` now disables all of it, but the **`WEB_PASSWORD`** it still uses (defense in depth) must be created as a `Secret` first — the manifest deliberately does not contain a literal password (this repo is public).

```bash
kubectl create secret generic comfyui-web-auth \
  --from-literal=WEB_PASSWORD='<generate-a-strong-password-yourself>' \
  -n comfyui
```

Generate the password yourself (e.g. a password manager, or `openssl rand -base64 24`) — don't reuse a password from anywhere else. Create the `comfyui` namespace first if it doesn't exist yet (`00-namespace.yaml`, below) since the Secret needs to go into it.

## Apply

```bash
sudo k3s kubectl apply -f infra/k8s/base/comfyui/00-namespace.yaml
# create the comfyui-web-auth Secret here, per above, before applying the Deployment
sudo k3s kubectl apply -f infra/k8s/base/comfyui/01-comfyui.yaml
```

Deploys with **`replicas: 0`** — it won't actually start until you scale it up (see below). This is deliberate.

## Why replicas: 0, and how to switch between Ollama and ComfyUI

`gpu-node-01` has one physical GPU. Kubernetes' NVIDIA device plugin only advertises **one** allocatable `nvidia.com/gpu` unit on it, so Ollama and ComfyUI can't both hold a GPU reservation as always-on Deployments — whichever tries to schedule second will sit `Pending` with `Insufficient nvidia.com/gpu`. Until there's a real need for both running simultaneously (at which point NVIDIA GPU time-slicing is the proper fix — not set up yet), switch between them manually:

```bash
# Switch to ComfyUI
sudo k3s kubectl scale deployment/ollama -n ollama --replicas=0
sudo k3s kubectl scale deployment/comfyui -n comfyui --replicas=1

# Switch back to Ollama
sudo k3s kubectl scale deployment/comfyui -n comfyui --replicas=0
sudo k3s kubectl scale deployment/ollama -n ollama --replicas=1
```

## Access from the LAN (e.g. the Dell G5)

`http://<any-node-ip>:30188` (e.g. `http://192.168.0.106:30188`) once scaled up and the pod is `Running`.

## First model

No checkpoint is pre-loaded — ComfyUI needs at least one to generate anything. A standard first pick: SDXL base (~7GB). Either use ComfyUI's own model manager in the UI once it's up, or download directly into the pod:

```bash
sudo k3s kubectl exec -n comfyui deploy/comfyui -- wget -P /root/.comfy/models/checkpoints \
  https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors
```

Gated models (SD3, FLUX, etc.) need an `HF_TOKEN` env var set on the Deployment (Hugging Face account + accepted model license) — not configured yet, add as a follow-up if needed.

## First-deploy verification checklist

This is a first-pass deployment (image/volume layout taken from `ai-dock`'s documented example, not yet confirmed against actual pod behavior on this cluster). After scaling up, check:

```bash
sudo k3s kubectl logs -n comfyui deploy/comfyui --tail=80
```

- **Security first**: confirm no `trycloudflare.com` tunnel URLs appear anywhere in the log — if they do, `CF_QUICK_TUNNELS=false` didn't take effect; scale to 0 immediately and investigate before doing anything else (see ADR 0012).
- Does ComfyUI actually start and listen on 8188, or does the container expect different paths/env vars than configured in `01-comfyui.yaml`?
- Does it detect the GPU (look for CUDA/device init messages, similar to what Ollama's logs showed)?
- Do the model/output volume mounts match what the image actually reads/writes from — adjust `01-comfyui.yaml`'s `volumeMounts` if not.

Update this README and the manifest once verified; note here if anything needed correcting from the first-pass assumptions.
