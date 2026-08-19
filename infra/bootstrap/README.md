# bootstrap/

Scripts and notes for bringing a bare node to a known-good state before it joins the cluster:

1. Base OS updates and required packages — [`install-base-packages.sh`](install-base-packages.sh)
2. Non-root admin user with sudo
3. SSH hardening (key-only auth, disabled password/root login, stable static IP or DHCP reservation) — [`install-ssh.sh`](install-ssh.sh), [`harden-ssh.sh`](harden-ssh.sh)
4. NVIDIA driver + container toolkit install (GPU nodes only)
5. Firewall / basic network config

Run `install-base-packages.sh` first on any new or reimaged node — it wasn't written until after `control-plane-01` turned out to be missing `curl` mid-way through k3s install, so don't assume general tooling is present just because SSH bootstrap ran.

Each node's bootstrap run should be recorded in [`docs/hardware/`](../../docs/hardware/) (what was done, when, and any quirks specific to that box).
