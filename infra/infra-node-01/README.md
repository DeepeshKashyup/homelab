# infra-node-01/

Services running directly on `infra-node-01` (Lenovo ThinkCentre M700 Tiny) — **not** Kubernetes manifests. This node deliberately doesn't join the k3s cluster; see [ADR 0013](../../docs/decisions/0013-infra-node-dedicated-services-adguard-dns.md) for why, and why AdGuard Home + Docker for its first service.

## Setup order

1. Node bootstrap (SSH, hardening, base packages) — same `infra/bootstrap/` flow as the other two nodes. Done.
2. Install Docker: `sudo bash infra/infra-node-01/install-docker.sh`
3. Open the firewall for DNS: `sudo bash infra/infra-node-01/open-dns-firewall.sh`
4. Deploy AdGuard Home:
   ```bash
   cd infra/infra-node-01/adguardhome
   docker compose up -d
   ```
5. Complete the first-run setup wizard at `http://192.168.0.82:3000` — when asked for the permanent admin interface port, keep `3000`.
6. Point your router's DHCP-advertised DNS server at `192.168.0.82` (or configure it per-device) so LAN clients actually use it. Not done automatically — this is a router config change outside this repo's scope.

## Adding local hostnames (the actual point of this — see ADR 0009)

Once AdGuard Home is up: **Filters → DNS rewrites** → add entries like `openwebui.homelab.local → 192.168.0.106`, `comfyui.homelab.local → 192.168.0.79`. This is the prerequisite for the eventual NodePort → Traefik Ingress migration.

## Vikunja (backlog / Kanban board)

Second service on this node — a lightweight backlog tracker for homelab work (ADR follow-ups, on-the-horizon items), kept off the k3s cluster deliberately so it's still reachable if the cluster it's tracking work for is down. See `docs/decisions/0014` and the `vikunja/docker-compose.yml` header comment.

1. Open the firewall: `sudo bash infra/infra-node-01/open-vikunja-firewall.sh`
2. Generate a JWT secret (not checked into git):
   ```bash
   cd infra/infra-node-01/vikunja
   echo "VIKUNJA_JWT_SECRET=$(openssl rand -base64 32)" > .env
   ```
3. Create the data directories **and chown them to uid 1000** before first start — Vikunja's process runs as uid 1000 inside the container, and if Docker auto-creates these as root on first `up`, the container fails with "permission denied":
   ```bash
   mkdir -p data/files data/db
   sudo chown -R 1000:1000 data
   ```
4. Deploy:
   ```bash
   docker compose up -d
   ```
5. Complete the first-run signup at `http://192.168.0.82:3456` (first account created becomes admin — no separate claim/invite flow). Use the **IP**, not a hostname, for this — see the gotcha below.
6. **Done** (2026-08-22): DNS rewrite added (`kanban.homelab.local → 192.168.0.82`) and `VIKUNJA_SERVICE_PUBLICURL` switched to the hostname. Use `http://kanban.homelab.local:3456` — but only from a client that actually queries AdGuard Home for DNS. The router isn't in bridge mode yet, so this isn't DHCP-wide: each client needs its own DNS pointed at `192.168.0.82` until then (see the "DNS without router changes" note below). A client without that gets the same "network error" the initial setup hit — fall back to `http://192.168.0.82:3456` for it instead.

### DNS without router changes (per-device, until bridge mode)

The router (ISP-provided) doesn't expose DHCP-wide DNS server configuration without bridge mode + a separate router behind it — not done yet, tracked in `docs/decisions/0014`. Until then, `*.homelab.local` names (this one, `openwebui.homelab.local`, etc.) only resolve for clients explicitly pointed at `192.168.0.82` as their DNS server:

- **Windows**: Settings → Network & Internet → Wi-Fi → your network → Edit DNS settings → Manual → IPv4 → Preferred DNS = `192.168.0.82` (no secondary — AdGuard Home already forwards non-local queries upstream itself; adding a public secondary can cause a client to intermittently query it directly and get `NXDOMAIN` for local rewrites instead of AdGuard's answer).
- **Fire TV / phone**: same idea via the network's advanced/static IP settings, per device.

**Watch for VPN clients silently breaking this even after it's configured** — hit twice in one session (2026-08-22): NordVPN and PIA on the Dell G5 both route LAN-destined traffic through their tunnels by default, which breaks DNS to `192.168.0.82` (times out) exactly like it broke bulk transfers to `control-plane-01` (see `infra/k8s/base/plex/README.md`). Fix per-VPN: NordVPN Settings → LAN Discovery; PIA Settings → Network → Allow LAN traffic. Until that's enabled, disconnect the VPN before relying on `*.homelab.local` resolution.

   **Gotcha hit during initial setup**: `VIKUNJA_SERVICE_PUBLICURL` isn't just cosmetic — the frontend uses it as the base URL for its own API calls (registration, login, everything). Setting it to `kanban.homelab.local` *before* the DNS rewrite + client DNS pointing above were actually in place caused a generic "network error" on account creation, because the browser couldn't resolve that hostname at all yet. Keep this set to the working IP until the hostname is verified resolving from wherever you're accessing it.
