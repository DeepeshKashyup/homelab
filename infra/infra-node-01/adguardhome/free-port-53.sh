#!/usr/bin/env bash
# infra/infra-node-01/adguardhome/free-port-53.sh
#
# Frees port 53 for AdGuard Home by disabling systemd-resolved's local
# stub listener (127.0.0.53:53 / 127.0.0.54:53), which otherwise conflicts
# with Docker's wildcard 0.0.0.0:53 bind — Docker refuses to start the
# AdGuard Home container with "address already in use" until this is
# done. systemd-resolved itself keeps working for everything else; only
# its stub proxy on port 53 is disabled. /etc/resolv.conf is repointed to
# the non-stub file so the host doesn't lose DNS resolution in the
# process.
#
# Run with sudo on infra-node-01, BEFORE `docker compose up`:
#   sudo bash infra/infra-node-01/adguardhome/free-port-53.sh

set -euo pipefail

echo "==> Disabling systemd-resolved's stub listener"
mkdir -p /etc/systemd/resolved.conf.d
cat > /etc/systemd/resolved.conf.d/no-stub-listener.conf <<'EOF'
[Resolve]
DNSStubListener=no
EOF

echo "==> Repointing /etc/resolv.conf to the non-stub resolv.conf"
ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf

echo "==> Restarting systemd-resolved"
systemctl restart systemd-resolved

echo
echo "==> Confirming port 53 is free"
if ss -tlnp | grep -q ':53 '; then
  echo "WARNING: something is still listening on :53 — check 'ss -tlnp | grep :53'"
  ss -tlnp | grep ':53 '
else
  echo "OK: nothing listening on :53"
fi

echo
echo "Done. Host DNS resolution still works (via /run/systemd/resolve/resolv.conf's"
echo "real upstream servers). Retry: docker compose up -d"
