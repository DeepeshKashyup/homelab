#!/usr/bin/env bash
# infra/bootstrap/harden-ssh.sh
#
# Phase 2 of node bootstrap: lock SSH down to key-only auth.
#
# ONLY run this AFTER you've confirmed you can log in with a key from the
# jump box (Dell G5) — e.g.:
#   ssh-copy-id deepesh@<node-ip>
#   ssh deepesh@<node-ip>   # confirm this works with no password prompt
#
# Run with sudo on the target node:
#   sudo bash infra/bootstrap/harden-ssh.sh

set -euo pipefail

SSHD_CONFIG="/etc/ssh/sshd_config"
DROPIN_DIR="/etc/ssh/sshd_config.d"
DROPIN="$DROPIN_DIR/99-hardening.conf"

if [ ! -f "$SSHD_CONFIG" ]; then
  echo "sshd_config not found — is openssh-server installed? Run install-ssh.sh first." >&2
  exit 1
fi

mkdir -p "$DROPIN_DIR"

cat > "$DROPIN" <<'EOF'
# Managed by infra/bootstrap/harden-ssh.sh — key-only auth, no root login.
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
EOF

echo "==> Wrote $DROPIN"
cat "$DROPIN"

echo "==> Validating sshd config"
sshd -t

echo "==> Restarting ssh.service"
systemctl restart ssh

echo
echo "Done. Password auth is now disabled — key-only from here on."
echo "Keep your current session open until you've verified a fresh"
echo "'ssh deepesh@<node-ip>' from the jump box still works."
