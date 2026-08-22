# plex/

Plex Media Server (movie library) in the `plex` namespace, pinned to `control-plane-01` — see [ADR 0009](../../../../docs/decisions/0009-nodeport-then-traefik-ingress.md) for why this is exposed via `NodePort`, and `01-plex.yaml`'s header comment for why `control-plane-01` over `gpu-node-01`.

## Apply

```bash
sudo k3s kubectl apply -f infra/k8s/base/plex/00-namespace.yaml
sudo k3s kubectl apply -f infra/k8s/base/plex/01-plex.yaml
```

No firewall change needed — `32400` already falls inside the NodePort range opened by [`infra/k8s/open-nodeport-firewall.sh`](../../open-nodeport-firewall.sh), which `control-plane-01` already has open from its k3s server install.

## First-run setup (claim the server)

No `PLEX_CLAIM` token is baked into the manifest (it's only valid ~4 minutes, not something to check in). Once the pod is `Running`:

1. From a browser on the LAN, go to `http://192.168.0.106:32400/web`.
2. Sign in with your Plex account and step through the setup wizard.
3. When it asks you to add a library, point it at `/movies` (that's where `plex-media` is mounted) and name it "Movies".

## Getting a movie file onto the media PVC

The `plex-media` PVC is `local-path` (host-backed on `control-plane-01`'s disk, ~800GB free), but its actual host directory is auto-generated and not predictable ahead of time — so don't try to `scp` straight to it. Two-step transfer instead, same spirit as how ComfyUI's first model got pulled in (`kubectl exec ... wget`, i.e. always write into the volume from inside the cluster, not by guessing the host path):

```bash
# 1. Get the file onto control-plane-01 itself (normal scp, full LAN speed)
scp "C:\path\to\movie.mkv" deepesh@control-plane-01:~/movie.mkv

# 2. Copy it from the node into the running pod's /movies mount
#    (kubectl cp, local disk-to-disk on the same box — fast)
sudo k3s kubectl cp ~/movie.mkv plex/$(sudo k3s kubectl get pod -n plex -l app=plex -o jsonpath='{.items[0].metadata.name}'):/movies/movie.mkv

# 3. Clean up the temp copy on control-plane-01 once step 2 finishes
rm ~/movie.mkv
```

For a ~70GB file, expect step 1 to be the slow part (`control-plane-01` is on Wi-Fi, not wired — see CLAUDE.md's "on the horizon" note about switching it to Ethernet). Step 2 should be quick since it's local to the node.

## First-deploy verification checklist

```bash
sudo k3s kubectl logs -n plex deploy/plex --tail=80
sudo k3s kubectl get pods -n plex
```

- Does the pod reach `Running` cleanly, no crash-loop?
- Is `http://192.168.0.106:32400/web` reachable from the Dell G5 browser?
- After the two-step file transfer, does the movie show up once you scan the "Movies" library (Plex should auto-scan on file changes, or trigger manually from the library's "..." menu)?
- Does playback work via Direct Play from a LAN client? (Transcoding isn't configured — a client requesting an unsupported format/bitrate will fail rather than transcode; that's expected for now.)

Update this README once verified — note here if the image tag, mount paths, or transfer flow needed correcting from what's assumed above.
