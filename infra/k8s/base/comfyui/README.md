# comfyui/

ComfyUI (image generation, GPU-scheduled on `gpu-node-01`) in the `comfyui` namespace. Image: `docker.io/yanwk/comfyui-boot:cu130-slim-v2` — plain ComfyUI + ComfyUI-Manager, no bundled extras. See [ADR 0008](../../../../docs/decisions/0008-nvidia-device-plugin-default-runtime.md) for GPU scheduling and [ADR 0009](../../../../docs/decisions/0009-nodeport-then-traefik-ingress.md) for why this is exposed via `NodePort`.

**This wasn't the first image tried.** `ghcr.io/ai-dock/comfyui` was tried first and caused a real security incident (auto-exposed public tunnels with a weak default password) plus two other blockers (Kubernetes-incompatible port automation, and a bundled PyTorch too old for the RTX 5060 Ti's Blackwell architecture). Full writeup in [ADR 0012](../../../../docs/decisions/0012-comfyui-public-tunnel-security-incident.md) — worth reading before reaching for another "convenience" image bundling extra services in this cluster.

## Apply

```bash
sudo k3s kubectl apply -f infra/k8s/base/comfyui/00-namespace.yaml
sudo k3s kubectl apply -f infra/k8s/base/comfyui/01-comfyui.yaml
```

Deploys with **`replicas: 0`** — it won't actually start until you scale it up (see below). This is deliberate.

Also needs the NodePort range open in `ufw` on whichever node(s) will serve it — see [`infra/k8s/open-nodeport-firewall.sh`](../../open-nodeport-firewall.sh); run it on both nodes if not already done (it's idempotent).

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

No checkpoint is pre-loaded — ComfyUI needs at least one to generate anything. A standard first pick: SDXL base (~7GB). Either use ComfyUI-Manager's model download UI once it's up, or download directly into the pod:

```bash
sudo k3s kubectl exec -n comfyui deploy/comfyui -- wget -P /root/ComfyUI/models/checkpoints \
  https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors
```

Gated models (SD3, FLUX, etc.) need a Hugging Face token — check `yanwk/comfyui-boot`'s docs for how it expects that passed (not yet configured here).

## First-deploy verification checklist

```bash
sudo k3s kubectl logs -n comfyui deploy/comfyui --tail=80
```

- Does ComfyUI start cleanly and detect the GPU without the `sm_120 is not compatible` warning that killed the previous image? Should show a normal CUDA device init instead.
- Does it actually bind reachably (not loopback-only) — confirm with `curl http://<node-ip>:30188/` once the pod is `Running`.
- Do the model/output volume mounts (`/root/ComfyUI/models`, `/root/ComfyUI/output`) match what this image actually uses — adjust `01-comfyui.yaml` if not.

Update this README once verified; note here if anything needed correcting from the current assumptions (image reference/tags for this project move fast — pin to a specific tag if `cu130-slim-v2` gets superseded and behavior changes).
