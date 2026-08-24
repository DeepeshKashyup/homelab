<#
.SYNOPSIS
  Sends Wake-on-LAN magic packets to control-plane-01 and gpu-node-01.

.DESCRIPTION
  Only works once, for each machine:
    1. Wake-on-LAN is enabled in that machine's BIOS/UEFI (look for
       "Wake on LAN", "Power On by PCI-E", or "Resume by LAN"), and any
       "ErP"/"EuP" power-saving option is off (it can cut NIC power
       entirely when the machine is shut down, defeating WoL regardless
       of everything else here).
    2. infra/bootstrap/enable-wol.sh has been run on that machine (OS-side
       persistent wol=magic setting).

  Neither of those is done as of 2026-08-24 -- see the Vikunja backlog
  item for Wake-on-LAN setup. This script is prepared ahead of that so
  it is ready to use once both steps are done on a machine.

  Sends the standard 102-byte magic packet (6 bytes of 0xFF followed by
  the target MAC repeated 16 times) as a UDP broadcast to port 9, which
  works because both nodes are on the same LAN segment as this jump box.

.EXAMPLE
  .\wake-cluster.ps1
  Wakes both nodes.

.EXAMPLE
  .\wake-cluster.ps1 -Node gpu-node-01
  Wakes only gpu-node-01.
#>

param(
    [ValidateSet('control-plane-01', 'gpu-node-01', 'both')]
    [string]$Node = 'both'
)

$ErrorActionPreference = 'Stop'

# MAC addresses of each node's wired NIC (the interface that matters for
# WoL) -- see docs/hardware/pc2-control-plane.md and pc1-gpu-node.md.
$macs = @{
    'control-plane-01' = 'e8:d8:d1:b9:06:f3'  # eno1
    'gpu-node-01'       = 'd8:5e:d3:05:3e:af'  # enp6s0
}

function Send-MagicPacket {
    param([string]$Mac)

    $macBytes = $Mac.Split(':') | ForEach-Object { [byte]([Convert]::ToInt32($_, 16)) }
    $packet = [byte[]](, 0xFF * 6)
    for ($i = 0; $i -lt 16; $i++) {
        $packet += $macBytes
    }

    $udpClient = New-Object System.Net.Sockets.UdpClient
    $udpClient.EnableBroadcast = $true
    $udpClient.Connect(([System.Net.IPAddress]::Broadcast), 9)
    $udpClient.Send($packet, $packet.Length) | Out-Null
    $udpClient.Close()
}

$targets = if ($Node -eq 'both') { $macs.Keys } else { @($Node) }

foreach ($name in $targets) {
    $mac = $macs[$name]
    Write-Host "==> Sending magic packet to $name ($mac)"
    Send-MagicPacket -Mac $mac
}

Write-Host ""
Write-Host "Done. Give it a minute, then check with: ssh control-plane-01 hostname"
Write-Host "(If nothing happens: confirm BIOS WoL is enabled and enable-wol.sh has been run on that machine.)"
