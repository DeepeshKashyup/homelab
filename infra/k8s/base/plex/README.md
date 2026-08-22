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

## Remote access (outside the LAN — e.g. a Fire TV app off-network)

**Plex's automatic UPnP remote-access setup can't work here.** Plex normally asks your router directly (via UPnP) to open a port back to itself, but this Plex process runs inside a pod on Kubernetes' internal overlay network (a `10.42.x.x` address) — it has no route to your actual router's UPnP API. This is a structural consequence of the NodePort deployment, not a misconfiguration; automatic remote access will silently fail regardless of anything in the Plex UI.

Do it manually instead:

1. In Plex **Settings → Network**, check "Manually specify public port" and set it to `32400`.
2. On the router, add a port-forward: external `32400` (TCP) → internal `192.168.0.106:32400` (the node's stable Wi-Fi address — **not** `.47`, which is a plain DHCP lease that can change; see the transfer-gotchas section above). No extra `ufw` change needed, same reasoning as the Apply section above.
3. Confirm Plex Settings → Network flips to "Fully accessible" (green).
4. If it still doesn't work, check whether the ISP is doing CGNAT (router's WAN IP doesn't match what an external site reports as your public IP) — port forwarding can't work at all behind CGNAT, and the fix is different (e.g. Tailscale) rather than more router config.

Status as of 2026-08-22: guidance given, not yet confirmed working end to end from an actual outside network.

## Getting a movie file onto the media PVC

The `plex-media` PVC is `local-path` (host-backed on `control-plane-01`'s disk, ~800GB free), but its actual host directory is auto-generated and not predictable ahead of time — so don't try to transfer straight to it. Two-step transfer instead, same spirit as how ComfyUI's first model got pulled in (`kubectl exec ... wget`, i.e. always write into the volume from inside the cluster, not by guessing the host path):

```bash
# 1. Get the file onto control-plane-01 itself
sftp -i ~/.ssh/homelab_ed25519 -b batchfile deepesh@192.168.0.47   # see below for why .47 and why sftp, not scp

# 2. Copy it from the node into the running pod's /movies mount
#    (kubectl cp, local disk-to-disk on the same box — fast)
sudo k3s kubectl cp ~/movie.mkv plex/$(sudo k3s kubectl get pod -n plex -l app=plex -o jsonpath='{.items[0].metadata.name}'):/movies/movie.mkv

# 3. Clean up the temp copy on control-plane-01 once step 2 finishes
rm ~/movie.mkv
```

### Step 1 gotchas, hit for real testing with two Blu-ray remux files (2026-08-22)

**Use `192.168.0.47` (wired), not the `control-plane-01` alias (`.106`, Wi-Fi) — and don't use plain `scp`.** In order, here's what broke and why:

1. **`control-plane-01` was Wi-Fi-only and capped around ~3.6MB/s** — two compounding causes. First, the sending machine (Dell G5) had two VPN clients active at once (NordVPN, PIA), both routing LAN-destined traffic through the tunnel instead of directly over Wi-Fi (pings to a same-room device were 52–495ms instead of <5ms — check `ping <target>` for this symptom before blaming Wi-Fi). Second, even with VPN off, `control-plane-01`'s USB Wi-Fi adapter turned out to be **2.4GHz-only hardware** (confirm with `iw phy | grep MHz` — no 5GHz band listed at all means this ceiling, not a config issue). Fix: physically wire `control-plane-01` via Ethernet. It grabbed its own DHCP address, `192.168.0.47`, immediately — use that IP directly for transfers (don't route through `.106`). Since it's a raw IP, `~/.ssh/config`'s `IdentityFile` for the `control-plane-01` alias won't apply — pass `-i ~/.ssh/homelab_ed25519` explicitly.
2. **Even wired, plain `scp` of a large (~64GB) file reset consistently around ~800–860MB in** — `client_loop: send disconnect: Connection reset` / `Broken pipe`, both times at a similar (sub-1GB) point. Disk space and NIC error counters were both clean, so this looks like an SSH rekey-boundary issue on sustained high-throughput transfers rather than a real network fault. Worked around with `sftp`'s `reput` (resume-put) command instead of `scp`, wrapped in a shell retry loop so a drop just resumes from the destination's current byte offset rather than restarting:
   ```bash
   until sftp -i ~/.ssh/homelab_ed25519 -o ConnectTimeout=8 -b batchfile deepesh@192.168.0.47; do
     echo "sftp dropped, retrying in 5s..."; sleep 5
   done
   ```
   where `batchfile` contains a single line: `reput "/path/to/movie.mkv" movie.mkv`. Got back to near-`scp` throughput (~20–28MB/s) while surviving drops. (A first attempt at a resumable transfer used `python -m http.server` + `wget -c` on the theory that plain HTTP would dodge the SSH-specific issue — technically resumable, but Python's built-in HTTP server turned out to be much slower in practice, ~4–7MB/s. `sftp reput` gets both properties: native-OpenSSH speed and resumability.)
3. **Don't use `pkill -f "<pattern>"` to clean up a stuck transfer if the pattern also appears in the `pkill` command's own argv** — it can match and kill itself, dropping the SSH session before the actual target process dies. Use `pgrep`/`ps` to find the exact PID and `kill <pid>` instead.

`control-plane-01`'s `.47` address is **plain DHCP, not a stable/reserved address** — fine for a manual one-off transfer, but don't hardcode it anywhere long-lived. `.106` (Wi-Fi) remains the node's official/stable identity for now (see CLAUDE.md for why promoting `.47` to primary is deferred as its own, more careful change).

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
