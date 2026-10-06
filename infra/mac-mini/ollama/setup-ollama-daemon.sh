#!/usr/bin/env bash
# infra/mac-mini/ollama/setup-ollama-daemon.sh
#
# Moves Ollama from Homebrew's per-user LaunchAgent to a system LaunchDaemon
# bound to 0.0.0.0:11434 (see com.homelab.ollama.plist for why).
#
# Run on the Mac Mini, from the repo root:
#   sudo bash infra/mac-mini/ollama/setup-ollama-daemon.sh
#
# Idempotent — safe to re-run after editing the plist.

set -euo pipefail

LABEL="com.homelab.ollama"
SRC="$(cd "$(dirname "$0")" && pwd)/$LABEL.plist"
DEST="/Library/LaunchDaemons/$LABEL.plist"
RUN_USER="homelab-mac-01"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run with sudo." >&2
  exit 1
fi

echo "==> Stopping Homebrew's ollama LaunchAgent (if running)"
# brew refuses to run as root; run it as the owning user.
sudo -u "$RUN_USER" /opt/homebrew/bin/brew services stop ollama || true

echo "==> Installing $DEST"
plutil -lint "$SRC"
cp "$SRC" "$DEST"
chown root:wheel "$DEST"
chmod 644 "$DEST"

echo "==> (Re)loading $LABEL"
launchctl bootout "system/$LABEL" 2>/dev/null || true
launchctl bootstrap system "$DEST"
launchctl enable "system/$LABEL"

sleep 3
echo "==> Listening sockets on 11434:"
lsof -nP -iTCP:11434 -sTCP:LISTEN || { echo "Ollama not listening — check /opt/homebrew/var/log/ollama.log" >&2; exit 1; }

echo
echo "Done. Do NOT run 'brew services start ollama' again — it would start a"
echo "second instance fighting over port 11434. After 'brew upgrade ollama',"
echo "restart with: sudo launchctl kickstart -k system/$LABEL"
