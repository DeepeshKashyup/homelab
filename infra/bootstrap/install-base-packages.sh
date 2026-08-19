#!/usr/bin/env bash
# infra/bootstrap/install-base-packages.sh
#
# Phase 0 of node bootstrap: base OS updates and the small set of packages
# every node needs regardless of role (git for cloning this repo, curl for
# installer scripts like k3s's, ca-certificates/gnupg for adding apt repos
# later, conntrack for diagnosing Kubernetes Service/DNAT networking
# issues — see docs/decisions/0010 for a real incident this was needed
# for: stale conntrack entries after a CoreDNS pod restart caused
# same-node pods to time out resolving cluster-internal DNS).
#
# This exists because install-ssh.sh only ever covered SSH-specific
# packages (openssh-server, ufw) — general tooling was assumed present and
# wasn't, which is why control-plane-01 was missing curl when the k3s
# installer needed it. Run this first on any new or reimaged node.
#
# Run with sudo on the target node:
#   sudo bash infra/bootstrap/install-base-packages.sh

set -euo pipefail

echo "==> Updating package lists and upgrading existing packages"
apt-get update -y
apt-get upgrade -y

echo "==> Installing base packages"
apt-get install -y \
  curl \
  git \
  ca-certificates \
  gnupg \
  htop \
  vim \
  conntrack

echo
echo "==> Versions"
for cmd in curl git conntrack; do
  echo -n "$cmd: "
  "$cmd" --version | head -1
done

echo
echo "Done."
