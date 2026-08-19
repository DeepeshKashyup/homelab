# ADR 0012: Disable ai-dock's Auto-Exposure Features (Security Incident)

**Status:** Accepted
**Date:** 2026-08-19
**Related to:** [ADR 0009](0009-nodeport-then-traefik-ingress.md) (this project's general exposure philosophy — deliberate LAN-only NodePort access, which this incident violated unintentionally)

Unlike the other incident ADRs (0008, 0010, 0011), this one is a **security** incident, not just a networking bug — it briefly exposed services to the public internet with a weak default credential. Documented in full because understanding what happened matters more than usual here.

## What happened

`infra/k8s/base/comfyui/01-comfyui.yaml` deployed `ghcr.io/ai-dock/comfyui:latest-cuda` with no environment variables beyond `AUTO_UPDATE=false`. On first startup, its logs showed something unexpected:

```
Your quick Tunnel has been created! Visit it at (it may take some time to be reachable):
https://colleges-mesh-while-stages.trycloudflare.com
```

...four times, for four different internal ports — including what appears to be Jupyter Notebook (port 8888) and syncthing (port 8384). The `ai-dock` image family is built for cloud GPU rental platforms (RunPod, vast.ai), where auto-generating a public URL to reach your rented GPU's services is the *point*. Nothing about that is appropriate for a private, self-hosted homelab node — but the image doesn't know the difference, and does it **by default**, with no opt-in required.

Worse: `ai-dock`'s documented default for `WEB_PASSWORD` (the credential gating these auto-exposed web services) is the literal string `"password"`. Combined, an unconfigured deploy of this image creates a small window where a service capable of arbitrary code execution (Jupyter) is reachable from the public internet, protected by a trivially guessable default.

**Caught and scaled to zero within minutes** of the pod starting, while reviewing its startup logs for an unrelated reason (confirming GPU detection and volume paths). No evidence was gathered on whether the tunnel URLs were actually accessed by anyone else in that window; treat as a near-miss, not a confirmed compromise, but act as if credentials/state on that node deserve a second look.

## Why this wasn't caught before deploying

Nothing in this project's earlier deploys (Ollama, Open WebUI) behaved this way — both are narrowly-scoped images that do exactly what their Dockerfile says and nothing else. `ai-dock/comfyui` is a different category of image: a full remote-development environment wrapper (`supervisor` managing many services: ComfyUI, Jupyter, syncthing, SSH, a service portal, Cloudflare tunnels) layered on top of the actual application. The research done before deploying (README docker-compose example) covered *how to run it*, not *what it does by default beyond the one service asked for* — the gap was assuming an image's scope matches the one thing you want from it.

## Decision

Explicitly disable every ai-dock convenience feature not needed here, rather than trusting defaults:

| Env var | Set to | Why |
|---|---|---|
| `CF_QUICK_TUNNELS` | `false` | The critical fix — no public internet tunnels, period. |
| `SSH_PORT_HOST` | `""` (disabled) | Unneeded — `kubectl exec` is the access path for this cluster. |
| `SYNCTHING_UI_PORT_HOST`, `SYNCTHING_TRANSPORT_PORT_HOST` | `""` (disabled) | Unneeded. |
| `SERVICEPORTAL_PORT_HOST` | `""` (disabled) | Unneeded — access is via ComfyUI's own NodePort directly. |
| `WEB_ENABLE_AUTH` | `true` | Already the default; set explicitly as defense in depth. |
| `WEB_PASSWORD` | a generated strong value, via a `Secret` | Never the default `"password"`. |

## Why `WEB_PASSWORD` is a Kubernetes `Secret`, not a literal in the manifest

This repository is **public** on GitHub. A literal credential in a committed YAML file is a credential leaked to the internet, permanently (git history doesn't forget, even if the file is later edited). `WEB_PASSWORD` is instead read via `secretKeyRef` from a `Secret` named `comfyui-web-auth`, created directly on the cluster and never committed:

```bash
kubectl create secret generic comfyui-web-auth \
  --from-literal=WEB_PASSWORD='<a-strong-password-you-generate-yourself>' \
  -n comfyui
```

Worth knowing: a Kubernetes `Secret` is base64-encoded, not encrypted — anyone with `kubectl get secret -o yaml` access to this cluster can trivially read it back out. That's an acceptable bar for a single-operator homelab; it would not be for a shared/multi-tenant cluster. The property that actually matters here is narrower and still holds: **it's not sitting in the git history of a public repository.**

## Consequences

- Every future third-party image deploy — especially anything billing itself as a "cloud-ready" / "RunPod-compatible" / "one-click" image — needs its startup logs checked for unexpected auto-exposure behavior *before* being treated as routine, not after. This class of image (bundling a supervisor + many auxiliary services) is categorically different from a narrowly-scoped application image and deserves more scrutiny, not the same default trust level as `ollama/ollama` or `ghcr.io/open-webui/open-webui`.
- Any secret needed by a future workload (API keys, tokens, passwords) follows the same pattern established here: `Secret` created out-of-band, referenced via `secretKeyRef`, never a literal in a committed manifest.
- Consider this a live reminder to periodically audit what's actually running/exposed on `gpu-node-01` and `control-plane-01` (`kubectl get pods -A`, check Service types), rather than assuming the repo's manifests are the complete picture of what's reachable.

## Follow-ups

- [x] Scale `comfyui` to 0 immediately upon discovery
- [x] Disable `CF_QUICK_TUNNELS` and all other unneeded auto-exposed services
- [x] Move `WEB_PASSWORD` to a `Secret`, generated fresh (not the image's default)
- [x] Redeploy with the fixed manifest and confirm no tunnel URLs appear in the logs on next startup — confirmed clean (no `cloudflared`/tunnel process at all)
- [ ] Decide whether to rotate any other credentials on `gpu-node-01`/`control-plane-01` out of an abundance of caution, given the exposure window (however brief)

## Postscript: switched images entirely

Even with the tunnel/password issue fixed, `ai-dock/comfyui` turned out to have two more problems unrelated to security: its Docker/RunPod-specific port-advertisement automation doesn't understand Kubernetes' own auto-injected Service env vars (ComfyUI never bound anywhere externally reachable), and its bundled PyTorch (2.4.1+cu121) doesn't support the RTX 5060 Ti's Blackwell architecture at all. Rather than keep patching around a vendor image built for a different deployment model, the project switched to `yanwk/comfyui-boot:cu130-slim-v2` — plain ComfyUI, no bundled extras, explicit Blackwell support. See `infra/k8s/base/comfyui/README.md` for the current setup. This ADR's security lesson (scrutinize "convenience" images bundling extra services; keep secrets out of a public repo) stands regardless of which image is in use.
