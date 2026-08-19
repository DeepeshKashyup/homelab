<#
.SYNOPSIS
  Shuts down both cluster nodes cleanly from the Dell G5 jump box.

.DESCRIPTION
  Runs `sudo shutdown now` on gpu-node-01 (worker) first, then
  control-plane-01 (server) — worker before control plane, same order
  you'd drain a real cluster in, even though it isn't strictly required
  for a 2-node homelab.

  What happens on next boot (see CLAUDE.md's "k3s cluster is up" section
  for the full explanation): k3s and k3s-agent are systemd-enabled, so
  they start automatically. Every Deployment resumes at whatever replica
  count was last set (persisted on disk, not just in memory) — so
  whichever of Ollama/ComfyUI was active when you shut down is what comes
  back active, not necessarily the one you want. Check
  infra/k8s/base/comfyui/README.md's scale commands if you need to switch
  after restarting. All models/data on PVCs persist regardless (they're
  plain directories on disk, untouched by a reboot).

  Both machines need a physical power-on afterward (no Wake-on-LAN set up)
  — this script only handles shutdown, not remote startup.

.EXAMPLE
  .\shutdown-cluster.ps1
#>

$ErrorActionPreference = 'Stop'

Write-Host "==> Shutting down gpu-node-01 (worker)"
ssh gpu-node-01 "sudo shutdown now"

Write-Host "==> Shutting down control-plane-01 (server)"
ssh control-plane-01 "sudo shutdown now"

Write-Host ""
Write-Host "Done. Both nodes are shutting down — physical power-on is needed to bring them back (no Wake-on-LAN configured)."
