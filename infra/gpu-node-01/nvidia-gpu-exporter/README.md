# nvidia-gpu-exporter/

Prometheus metrics exporter for `gpu-node-01`'s GPU — temperature, VRAM utilization, and power draw over time, for Grafana graphing. This is the "real graphs" follow-up that `infra/gpu-node-01/gpu-temp-exporter/README.md` explicitly deferred (that service stays as-is for Uptime Kuma's simple up/down alerting; this is for time-series charts).

Uses the community [`utkuozdemir/nvidia_gpu_exporter`](https://github.com/utkuozdemir/nvidia_gpu_exporter) (v1.14.0), installed via its `.deb` package — it ships its own systemd unit, so there's no custom script to maintain here (unlike `gpu-temp-exporter`, which is a small stdlib script we wrote ourselves).

**Runs directly on the host via systemd, not as a Kubernetes workload** — deliberately. It only needs to shell out to `nvidia-smi`, which is already on the host `PATH`; running it in-cluster would mean requesting the `nvidia.com/gpu` device-plugin resource (capacity 1 on this node) just to read stats, which would permanently block Ollama/ComfyUI's manual single-GPU toggle from ever scheduling. Prometheus (running in the `monitoring` namespace on `control-plane-01`) scrapes this host directly as a static target — see `infra/k8s/base/monitoring/values.yaml`.

## Deploy (on `gpu-node-01`)

```bash
cd ~/homelab && git pull
sudo bash infra/gpu-node-01/nvidia-gpu-exporter/install.sh
```

`install.sh` downloads the `.deb`, installs it, enables the systemd unit, opens the firewall, and verifies the metrics endpoint is returning real GPU data — see the script for the individual steps if running them by hand. Confirmed working 2026-08-25: `nvidia_smi_temperature_gpu`, `nvidia_smi_memory_used_bytes`/`memory_total_bytes`, `nvidia_smi_power_draw_watts` all present.

## Grafana

Once `infra/k8s/base/monitoring/values.yaml` is deployed and Prometheus is scraping this target, import the exporter's official dashboard into Grafana: **Dashboards → Import → ID `14574`** ("Nvidia GPU Metrics"). Set its Prometheus datasource to the `prometheus` datasource kube-prometheus-stack creates automatically.

## Why not fold this into `gpu-temp-exporter`

`gpu-temp-exporter` is a deliberately tiny stdlib-only JSON endpoint for Uptime Kuma's threshold check — extending it to also speak Prometheus text format and cover VRAM/power would mean re-implementing what this well-tested, actively maintained project already does, with an existing Grafana dashboard to match. Two small services, two clear jobs.
