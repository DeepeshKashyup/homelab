#!/usr/bin/env bash
# infra/mac-mini/harden-ssh.sh
#
# Phase 2 of SSH bootstrap: key-only auth, no root login — same drop-in as
# infra/bootstrap/harden-ssh.sh, adapted for macOS (launchd instead of
# systemctl). macOS's sshd_config already has `Include sshd_config.d/*`.
#
# ONLY run after key login works from both jump boxes (see enable-ssh.sh).
#
#   sudo bash infra/mac-mini/harden-ssh.sh

set -euo pipefail

DROPIN="/etc/ssh/sshd_config.d/099-hardening.conf"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run with sudo." >&2
  exit 1
fi

# Named 099-* so it sorts before macOS's own 100-macos.conf — sshd uses the
# FIRST value it sees for each option.
cat > "$DROPIN" <<'EOF'
# Managed by infra/mac-mini/harden-ssh.sh — key-only auth, no root login.
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
EOF

echo "==> Wrote $DROPIN"
cat "$DROPIN"

echo "==> Validating sshd config"
/usr/sbin/sshd -t

echo "==> Effective auth settings:"
/usr/sbin/sshd -T 2>/dev/null | grep -E "^(passwordauthentication|kbdinteractiveauthentication|permitrootlogin|pubkeyauthentication) "

# launchd's sshd is per-connection (inetd-style), so new connections pick up
# the config immediately — no restart needed.
echo
echo "Done. Keep this session open until a fresh 'ssh mac-mini' from a jump"
echo "box still works, and 'ssh -o PubkeyAuthentication=no ...' is refused."
