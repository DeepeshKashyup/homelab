# gpu-temp-exporter/

A tiny stdlib-only Python HTTP server exposing `gpu-node-01`'s GPU temperature as JSON, so Uptime Kuma (on `infra-node-01`) can poll it every 5 minutes and alert on overheating — motivated by the same recurring GPU hang incidents that Uptime Kuma's existing ping/TCP monitors were added for (see CLAUDE.md).

Runs directly on the host via systemd, **not** as a Kubernetes workload — this way it just shells out to `nvidia-smi` with no container GPU-passthrough plumbing to fight.

**Limitation, stated up front:** Uptime Kuma is an up/down monitor, not a metrics/graphing tool. This gives you pass/fail alerting (e.g. "GPU too hot") and the last-checked value, **not** a temperature-over-time chart. If you want real graphs, that's a Prometheus + exporter + Grafana stack — a bigger addition, deliberately not what this is.

## Deploy (on `gpu-node-01`)

```bash
sudo mkdir -p /opt/gpu-temp-exporter
sudo cp infra/gpu-node-01/gpu-temp-exporter/gpu_temp_exporter.py /opt/gpu-temp-exporter/
sudo cp infra/gpu-node-01/gpu-temp-exporter/gpu-temp-exporter.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now gpu-temp-exporter

# open the firewall (not covered by the existing NodePort range or k3s rules)
sudo ufw allow 9400/tcp
```

Verify: `curl http://localhost:9400/` should return `{"temperature_c": 39, "gpu": "NVIDIA GeForce RTX 5060 Ti"}` (or similar). From the LAN: `curl http://192.168.0.79:9400/`.

## Add the Uptime Kuma monitor (manual — no provisioning API, same limitation noted in `infra/infra-node-01/uptime-kuma/docker-compose.yml`)

1. Open Uptime Kuma (`http://192.168.0.82:3001`) → **Add New Monitor**.
2. Monitor Type: **HTTP(s) - Json Query**.
3. URL: `http://192.168.0.79:9400/`
4. Friendly Name: `gpu-node-01 GPU Temp`
5. Heartbeat Interval: `300` (5 minutes, as requested).
6. Json Query Expression (this is JSONata, not a bare field name — the comparison has to live in the expression itself): `temperature_c < 85`
7. Expected Value: `true`
8. Save.

**How this actually evaluates** (Uptime Kuma runs the Json Query Expression as JSONata against the response body): `temperature_c` extracts `39` from `{"temperature_c": 39, ...}`, the full expression `temperature_c < 85` evaluates to `true`, and since that matches the Expected Value (`true`), the monitor stays green. If the temperature reaches 85°C or higher, the expression evaluates to `false`, mismatches the expected `true`, and the monitor goes red/alerts. 85°C leaves headroom below where consumer NVIDIA GPUs typically start throttling — adjust the threshold in the expression if you'd rather alert earlier.

## Why a new service instead of reusing something existing

- Not a Kubernetes workload: putting this in the cluster would mean solving GPU-device-plugin access for a `curl`-sized script, for no benefit — `nvidia-smi` is already on the host `PATH`.
- No third-party dependencies: stdlib `http.server` only, so nothing to `pip install` on the node for something this small.
- Runs as the regular `deepesh` user, not a dedicated service account — `nvidia-smi` query subcommands don't need elevated privileges, and this doesn't manage any persistent state or write access worth isolating (unlike the removed native `ollama.service`, which got its own user because it ran a full model server).
