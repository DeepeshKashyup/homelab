#!/usr/bin/env bash
# infra/infra-node-01/install-docker.sh
#
# Installs Docker Engine (docker-ce) on infra-node-01 via Docker's official
# apt repository — not a curl-pipe-to-shell installer. Adds the current
# user to the docker group so docker commands don't need sudo afterward
# (takes effect on next login/new shell session).
#
# Run with sudo on infra-node-01:
#   sudo bash infra/infra-node-01/install-docker.sh

set -euo pipefail

echo "==> Adding Docker's official GPG key and apt repository"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list

echo
echo "==> Installing Docker Engine"
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo
echo "==> Adding $SUDO_USER to the docker group (takes effect on next login)"
usermod -aG docker "${SUDO_USER:-deepesh}"

echo
echo "==> Verifying"
systemctl is-active docker
systemctl is-enabled docker
docker --version
docker compose version

echo
echo "Done. Log out and back in (or start a new SSH session) for the docker"
echo "group membership to take effect — until then, docker commands need sudo."
