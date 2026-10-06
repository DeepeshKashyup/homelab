#!/usr/bin/env bash
# infra/mac-mini/enable-ssh.sh
#
# Phase 1 of SSH bootstrap: turn on macOS Remote Login (sshd), password auth
# still allowed so jump boxes can push their keys.
#
#   sudo bash infra/mac-mini/enable-ssh.sh
#
# Then, from each jump box:
#   MacBook Pro:  ssh-copy-id -i ~/.ssh/homelab_ed25519.pub homelab-mac-01@192.168.0.174
#   Dell G5 (PowerShell):
#     Get-Content $env:USERPROFILE\.ssh\homelab_ed25519.pub | ssh homelab-mac-01@192.168.0.174 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
#
# Once key login works from BOTH, run harden-ssh.sh.

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run with sudo." >&2
  exit 1
fi

# systemsetup needs Full Disk Access for the calling terminal on recent macOS;
# fall back to enabling the sshd launchd job directly if it refuses.
if ! systemsetup -setremotelogin on 2>/dev/null; then
  echo "==> systemsetup refused (no Full Disk Access?) — using launchctl instead"
  launchctl enable system/com.openssh.sshd
  launchctl bootstrap system /System/Library/LaunchDaemons/ssh.plist 2>/dev/null || true
fi

sleep 1
if nc -z -G 2 127.0.0.1 22; then
  echo "==> sshd listening on :22"
else
  echo "sshd not listening — enable via System Settings > General > Sharing > Remote Login" >&2
  exit 1
fi
