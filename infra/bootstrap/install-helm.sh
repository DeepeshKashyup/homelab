#!/usr/bin/env bash
# infra/bootstrap/install-helm.sh
#
# Installs Helm 3 via the official get-helm-3 script (standard, signed
# installer — same category as the k3s installer already used in
# infra/k8s/install-k3s-server.sh). Needed on control-plane-01 to deploy
# infra/k8s/base/monitoring/ (Prometheus + Grafana via kube-prometheus-stack)
# and any future Helm-packaged workload.
#
# The get-helm-3 script prompts for sudo itself when it moves the binary
# into /usr/local/bin — run this as your normal user, not with sudo:
#   bash infra/bootstrap/install-helm.sh

set -euo pipefail

if command -v helm >/dev/null 2>&1; then
  echo "==> Helm already installed: $(helm version --short)"
  exit 0
fi

echo "==> Downloading get-helm-3"
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o /tmp/get_helm.sh
chmod 700 /tmp/get_helm.sh

echo "==> Running installer (will prompt for sudo)"
/tmp/get_helm.sh
rm /tmp/get_helm.sh

echo
echo "==> Version"
helm version

echo
echo "Done."
