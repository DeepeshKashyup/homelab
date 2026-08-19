# ADR 0003: Kubernetes Distribution Choice — k3s over k9s

**Status:** Accepted
**Date:** 2026-08-18

## Context

The homelab is being built as a small, self-hosted Kubernetes environment with a simple control-plane + worker topology. This platform must be low-friction to bootstrap, easy to operate from a home network, and compatible with local ML workloads such as Ollama and GPU scheduling.

We need a Kubernetes runtime that is lightweight enough to run on modest Intel/AMD mini-PC hardware, while still supporting the core platform requirements we care about: API server, worker nodes, CNI, and a straightforward path to later add workloads and storage.

## Important clarification

`k9s` is not a Kubernetes distribution or control-plane alternative. It is a terminal UI for interacting with a Kubernetes cluster after it is already running. The actual decision here is between `k3s` and a more standard upstream bootstrap path such as `kubeadm`. The relevant comparison is runtime + installation method, not a UI tool.

## Options considered

1. **k3s**
   - Lightweight single-binary Kubernetes distribution
   - Very fast bootstrap on small Linux hosts
   - Good fit for edge / homelab / on-prem workloads
   - Lower operational overhead than full kubeadm-based installs
   - Handles control plane and worker node setup with minimal friction

2. **kubeadm + upstream Kubernetes**
   - Standard upstream Kubernetes experience
   - Greater compatibility with upstream documentation and defaults
   - More manual setup and more operational moving parts
   - Requires more care with networking, CNI, and cluster lifecycle management
   - Better fit for teams that want the full upstream experience and are willing to manage more complexity

3. **k9s as a tooling choice**
   - Useful for cluster inspection and interaction
   - Not a runtime and not a replacement for the cluster orchestrator itself
   - Best treated as an operational convenience layer, not a platform decision

## Decision

Use `k3s` as the Kubernetes runtime for the cluster.

Use `k9s` only as a convenience tool for cluster inspection/debugging after the cluster is running, not as the primary control-plane decision.

## Rationale

- The target cluster is intentionally small: one control plane, one GPU worker, and low operational overhead.
- `k3s` reduces bootstrap complexity and is well-suited to home-lab and edge-class hardware.
- The project prioritizes a simple, reliable path to: node bootstrapping, CNI install, and workload deployment.
- `k3s` has a smaller footprint and simpler runtime assumptions than a full upstream install, which aligns with the project’s incremental, low-risk approach.
- `kubeadm` would be a valid choice for a more standard upstream-first operation, but in this homelab it adds unnecessary setup and lifecycle complexity.
- `k9s` provides a nice debugging UX, but it does not provide the runtime or control plane itself; therefore it does not compete with `k3s` as a selection criterion.

## Consequences

- The cluster will be easier and faster to bootstrap on the two Linux nodes.
- The operation model remains lightweight, making it practical to iterate on the platform without large management overhead.
- We will still use `kubectl` and possibly `k9s` for day-2 operational tasks, but the cluster runtime remains `k3s`.
- Future architecture choices should document whether a change is about runtime selection, tooling, or both.

## Follow-ups

- [x] Install `k3s` on `control-plane-01`
- [x] Join `gpu-node-01` as a worker
- [x] Validate cluster readiness with `kubectl get nodes`
- [ ] Add a short ops note on helpful tooling (`kubectl`, `k9s`, `helm`) and their roles
