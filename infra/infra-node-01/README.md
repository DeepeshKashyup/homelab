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

Once AdGuard Home is up: **Filters → DNS rewrites** → add entries like `openwebui.homelab.local → 192.168.0.47`, `comfyui.homelab.local → 192.168.0.79`. This is the prerequisite for the eventual NodePort → Traefik Ingress migration.

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

### Migrated to the shared Postgres cluster (2026-08-31)

Vikunja's database moved from local SQLite to a dedicated `vikunja` database on the shared CloudNativePG cluster — see [ADR 0021](../../../docs/decisions/0021-vikunja-postgres-migration.md) for the full reasoning, including the real tradeoff accepted: Vikunja now depends on `control-plane-01`/k3s/Postgres being reachable, which cuts directly against this section's own "still reachable if the cluster is down" opening line. Reached over the LAN NodePort added in [ADR 0020](../../../docs/decisions/0020-postgres-nodeport-reversal.md) (`192.168.0.47:30432`), since this node is outside the k3s cluster and has no in-cluster Service DNS to use.

**Gotcha hit during migration**: `VIKUNJA_DATABASE_PORT` is silently ignored for a postgres connection (confirmed against Vikunja v2.5.0) — it always tried port `5432` regardless of what `DATABASE_PORT` was set to, both via environment variables and a mounted `config.yml`. The working fix, now in `docker-compose.yml`: embed the port directly in `VIKUNJA_DATABASE_HOST` as `"192.168.0.47:30432"` rather than a separate `DATABASE_PORT` field.

**Migration method** (real data migration, not a fresh start — unlike the Open WebUI/Grafana Postgres migrations, this is the actual backlog):
1. Stopped the container, force-checkpointed the SQLite WAL via Python's `sqlite3` module (`PRAGMA wal_checkpoint(TRUNCATE)`) — the `-wal` file was 4.2MB against a 638KB main db file, meaning a lot of recent activity hadn't been folded in yet; skipping this step would have silently migrated stale data.
2. Backed up the checkpointed file (`data/db/vikunja.db.pre-postgres-migration-backup-20260831`, kept indefinitely as a rollback path, never modified).
3. Ran a throwaway Vikunja container's own `migrate` command against the new empty Postgres database first, so the schema it created matches exactly what this Vikunja version expects — rather than trusting a generic tool to infer it.
4. Used `pgloader` (`dimitri/pgloader`, run as a throwaway container, not installed on this node) with `create no tables, data only` to load rows into that already-correct schema. Needed the data directory mounted **read-write**, not `:ro` — SQLite couldn't open the file at all read-only (needs to create its own lock/journal files even for a read connection).
5. Verified: row counts matched exactly between source and target for every table checked (`tasks 45=45`, `projects 2=2`, `users 1=1`, `buckets 9=9`, `sessions 1=1`), spot-checked specific known tasks' `done`/`priority`/`title` fields matched, and confirmed the live instance's API (including the pre-existing API token, which round-tripped correctly) returns the expected task counts post-cutover.

## Uptime Kuma (monitoring)

Third service on this node — uptime/status monitoring, starting with `gpu-node-01` (motivated by its recurring GPU hang incidents, see CLAUDE.md — a ping/TCP monitor at least catches a full node hang even without deep GPU health metrics). Same off-cluster reasoning as AdGuard Home and Vikunja.

1. Open the firewall: `sudo bash infra/infra-node-01/open-uptime-kuma-firewall.sh`
2. Deploy:
   ```bash
   cd infra/infra-node-01/uptime-kuma
   docker compose up -d
   ```
3. Complete first-run setup at `http://192.168.0.82:3001` (creates the admin account).
4. Add monitors through the web UI — no simple provisioning API for this one, unlike Vikunja, so this part can't be scripted. Start with:
   - **Ping**: `gpu-node-01` → `192.168.0.79`
   - **TCP**: `192.168.0.79:22` (SSH)
   - Optionally, TCP/HTTP checks on whichever of Ollama (`31434`) / ComfyUI (`30188`) is currently scaled up — expect the other to show "down", that's normal given the single-GPU toggle (see `infra/k8s/base/comfyui/README.md`), not a real alert.
5. Optional: add the DNS rewrite (`uptime.homelab.local → 192.168.0.82`) same as the other two services — remember it only resolves for clients pointed at AdGuard Home for DNS (see above).
