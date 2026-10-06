#!/usr/bin/env bash
# infra/mac-mini/configure-power.sh
#
# Server power profile: never sleep, power back on after an outage, keep
# Wake-on-LAN. Out of the box this Mac slept after 1 minute idle, which
# makes it unreachable as an always-on Ollama host.
#
# (The "never suspend" rule in CLAUDE.md is about the NVIDIA driver on
# gpu-node-01; on this box sleep is disabled simply because a server that
# sleeps isn't a server.)
#
#   sudo bash infra/mac-mini/configure-power.sh

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run with sudo." >&2
  exit 1
fi

# sleep 0        — never system-sleep
# disksleep 0    — never spin down / idle the disk
# autorestart 1  — boot automatically after a power failure
# womp 1         — Wake-on-LAN (magic packet)
# displaysleep left alone — the display sleeping is harmless.
pmset -a sleep 0 disksleep 0 autorestart 1 womp 1

echo "==> Current settings:"
pmset -g | grep -E "^ (sleep|disksleep|autorestart|womp|displaysleep) "
