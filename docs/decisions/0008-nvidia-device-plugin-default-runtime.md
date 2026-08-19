# ADR 0008: GPU Scheduling — Default NVIDIA Runtime + Node-Labeled Device Plugin

**Status:** Accepted
**Date:** 2026-08-18

## Context

`gpu-node-01` is the only node in the cluster with a GPU (RTX 5060 Ti); `control-plane-01` has none. `nvidia-container-toolkit` was already installed on `gpu-node-01` as part of its original hardware bring-up, but k3s's embedded containerd was not yet configured to use the NVIDIA runtime, and no device plugin was deployed — so `nvidia.com/gpu` was not a schedulable resource in Kubernetes.

Two decisions were needed:
1. How containers request the NVIDIA runtime: a Kubernetes `RuntimeClass` (opt-in per pod) vs. making `nvidia` the containerd default runtime on the node.
2. Where the NVIDIA device plugin DaemonSet runs: cluster-wide (relying on the plugin container to no-op on nodes without a GPU) vs. explicitly scoped to GPU nodes.

## Decision

- Configure containerd on `gpu-node-01` via `nvidia-ctk runtime configure --set-as-default`, making the NVIDIA runtime the default for **all** containers scheduled on that node. No `RuntimeClass` object is used.
- Label `gpu-node-01` with `nvidia.com/gpu.present=true` and scope the device plugin DaemonSet to that label via `nodeSelector`, rather than deploying it cluster-wide.

## Rationale

- With only one GPU node and no current plan for a second, per-pod `RuntimeClass` opt-in adds a layer of indirection with no present benefit — every workload intentionally placed on `gpu-node-01` is there to use the GPU.
- Making NVIDIA the default runtime on `gpu-node-01` only affects that node; `control-plane-01` is unaffected. If a second, non-GPU-bound workload needs to run on `gpu-node-01` later without the NVIDIA runtime, `RuntimeClass` can be introduced then — this default doesn't foreclose that path, it just isn't needed yet.
- Scoping the device plugin DaemonSet by `nodeSelector` avoids scheduling a pointless (and potentially crash-looping, since it expects NVML/GPU devices) pod on `control-plane-01`, and makes node intent explicit and visible via `kubectl get nodes --show-labels` rather than implicit from the DaemonSet's runtime behavior.
- Matches the project's incremental approach (ADR 0004): solve for the cluster that exists (one GPU node) rather than building generalized multi-GPU-node scheduling before there's a second GPU node to justify it.

## Consequences

- Any pod scheduled on `gpu-node-01` runs under the NVIDIA container runtime by default, whether or not it requests `nvidia.com/gpu` resources. This is acceptable currently since `gpu-node-01` is dedicated to GPU/inference workloads (see `CLAUDE.md` topology).
- Adding a second GPU node later, or wanting to run non-GPU workloads on `gpu-node-01` under the default runtime, would be a natural trigger to revisit this ADR and introduce `RuntimeClass`.
- The device plugin DaemonSet manifest lives at `infra/k8s/base/nvidia-device-plugin.yaml`, vendored in-repo (not applied from a remote URL) so the exact deployed version is tracked in git.

## Incident: broken CNI from an unseeded containerd template

The first run of `configure-nvidia-runtime.sh` pointed `nvidia-ctk runtime configure` at `config.toml.tmpl`, which didn't exist yet. `nvidia-ctk` created it from containerd's generic defaults rather than k3s's own generated config — losing the CNI bin/conf-dir paths and CRI settings k3s needs. Once `k3s-agent` restarted and regenerated `config.toml` from that generic template, its CRI plugin could no longer initialize the CNI (flannel) plugin, and kubelet looped indefinitely on `NetworkPluginNotReady: cni plugin not initialized` — `systemctl restart k3s-agent` never returned, since the unit couldn't reach a ready state.

Fix: remove the broken template, let `k3s-agent` regenerate `config.toml` from its correct built-in defaults, confirm it's healthy, **then** copy that correct `config.toml` to `config.toml.tmpl` before running `nvidia-ctk` — so `nvidia-ctk` edits k3s's real config in place instead of replacing it. `configure-nvidia-runtime.sh` now does this seeding automatically and verifies no CNI errors appear before declaring success.

## Follow-ups

- [x] Configure containerd NVIDIA runtime on `gpu-node-01` (`infra/k8s/configure-nvidia-runtime.sh`)
- [x] Label `gpu-node-01` and deploy the device plugin DaemonSet
- [x] Validate `nvidia.com/gpu` shows as an allocatable resource on `gpu-node-01`
- [ ] Run a test GPU pod to confirm end-to-end scheduling before installing Ollama
