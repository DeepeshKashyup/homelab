# comfyui/

ComfyUI (image generation, GPU-scheduled on `gpu-node-01`) in the `comfyui` namespace. Image: `ghcr.io/ai-dock/comfyui:latest-cuda`. See [ADR 0008](../../../../docs/decisions/0008-nvidia-device-plugin-default-runtime.md) for GPU scheduling and [ADR 0009](../../../../docs/decisions/0009-nodeport-then-traefik-ingress.md) for why this is exposed via `NodePort`.

## Apply

```bash
sudo k3s kubectl apply -f infra/k8s/base/comfyui/00-namespace.yaml
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
sudo k3s kubectl logs -n comfyui deploy/comfyui --tail=50
```

- Does ComfyUI actually start and listen on 8188, or does the container expect different paths/env vars than configured in `01-comfyui.yaml`?
- Does it detect the GPU (look for CUDA/device init messages, similar to what Ollama's logs showed)?
- Do the model/output volume mounts match what the image actually reads/writes from — adjust `01-comfyui.yaml`'s `volumeMounts` if not.

Update this README and the manifest once verified; note here if anything needed correcting from the first-pass assumptions.
