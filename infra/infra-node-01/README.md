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
6. Optional, later: switch to a friendly hostname. This needs two things done together, not just the DNS rewrite alone:
   - Add the DNS rewrite in AdGuard Home (**Filters → DNS rewrites**): `kanban.homelab.local → 192.168.0.82`.
   - Make sure the client you're using actually queries AdGuard Home for DNS (either the router's DHCP-advertised DNS server points at `192.168.0.82` — see the AdGuard Home section above — or the specific device is configured to use it directly). Verify with `nslookup kanban.homelab.local` from that client before relying on it.
   - Only then update `VIKUNJA_SERVICE_PUBLICURL` in `docker-compose.yml` to the hostname and `docker compose up -d` again.

   **Gotcha hit during initial setup**: `VIKUNJA_SERVICE_PUBLICURL` isn't just cosmetic — the frontend uses it as the base URL for its own API calls (registration, login, everything). Setting it to `kanban.homelab.local` *before* the DNS rewrite + client DNS pointing above were actually in place caused a generic "network error" on account creation, because the browser couldn't resolve that hostname at all yet. Keep this set to the working IP until the hostname is verified resolving from wherever you're accessing it.
