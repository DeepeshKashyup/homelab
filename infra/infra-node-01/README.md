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
