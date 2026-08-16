# bootstrap/

Scripts and notes for bringing a bare node to a known-good state before it joins the cluster:

1. Base OS updates and required packages
2. Non-root admin user with sudo
3. SSH hardening (key-only auth, disabled password/root login, stable static IP or DHCP reservation)
4. NVIDIA driver + container toolkit install (GPU nodes only)
5. Firewall / basic network config

Each node's bootstrap run should be recorded in [`docs/hardware/`](../../docs/hardware/) (what was done, when, and any quirks specific to that box).
