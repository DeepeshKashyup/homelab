#!/usr/bin/env python3
"""Tiny JSON HTTP endpoint exposing gpu-node-01's GPU temperature via nvidia-smi.

Not a Kubernetes workload -- runs directly on the host as a systemd service
(see gpu-temp-exporter.service), so it can shell out to nvidia-smi without
any container GPU-passthrough plumbing. Built to give Uptime Kuma (on
infra-node-01) something to poll every 5 minutes via its "HTTP(s) - Json
Query" monitor type -- see this directory's README for the monitor setup
(Uptime Kuma has no provisioning API, so that part is manual, same
limitation noted in infra/infra-node-01/uptime-kuma/docker-compose.yml).

No third-party dependencies deliberately -- stdlib only, so nothing to pip
install on the node for a script this small.
"""

import json
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = 9400  # matches the conventional dcgm-exporter port; no functional tie to it here


def read_gpu_temp():
    """Returns (temperature_celsius, gpu_name), or (None, None) on failure."""
    try:
        out = subprocess.run(
            [
                "nvidia-smi",
                "--query-gpu=temperature.gpu,name",
                "--format=csv,noheader,nounits",
            ],
            capture_output=True,
            text=True,
            timeout=5,
            check=True,
        )
        temp_str, name = (p.strip() for p in out.stdout.strip().split(",", 1))
        return int(temp_str), name
    except Exception:
        return None, None


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        temp, name = read_gpu_temp()
        if temp is None:
            self.send_response(503)
            body = json.dumps({"error": "nvidia-smi query failed"}).encode()
        else:
            self.send_response(200)
            body = json.dumps({"temperature_c": temp, "gpu": name}).encode()
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass  # keep journald quiet -- this gets polled every 5 minutes forever


if __name__ == "__main__":
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"gpu-temp-exporter listening on :{PORT}")
    server.serve_forever()
