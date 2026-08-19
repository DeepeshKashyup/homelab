# ADR 0007: Bootstrap k3s with Bundled Flannel, Migrate to Cilium Later

**Status:** Accepted
**Date:** 2026-08-18
**Related to:** [ADR 0003](0003-k3s-over-k9s.md)

## Context

`k3s` ships with `flannel` as its default CNI, installed automatically unless disabled at install time. The platform's intended end-state CNI is Cilium (see the tools/resources list in `CLAUDE.md`), chosen for its eBPF-based networking and richer network-policy capabilities compared to flannel.

At the point of first cluster bring-up, the priority is validating that `k3s` itself installs and runs correctly on `control-plane-01` and that `gpu-node-01` can join as a worker. Introducing a non-default CNI in the same step (`--flannel-backend=none --disable-network-policy` plus a Cilium install) multiplies the number of things that can go wrong in the first bring-up, before there is a working baseline to fall back to.

## Decision

Install `k3s` with its bundled `flannel` CNI for the initial cluster bring-up. Treat the migration to Cilium as a separate, deliberate follow-up step once the base cluster (control plane + GPU worker, `kubectl get nodes` healthy) is validated.

## Rationale

- Isolates risk: a first-bring-up failure will be attributable to `k3s`/node config, not CNI swap-out mechanics happening in the same step.
- Matches the project's incremental, low-risk approach (see ADR 0004): prove the smallest working baseline first, then layer in the intended end-state component.
- CNI migration on a cluster with no real workloads yet is low-cost — there is nothing running that a network policy or CNI restart could disrupt at this stage.
- Cilium remains the intended target CNI; this ADR does not change that, only the sequencing.

## Consequences

- Initial cluster validation (`kubectl get nodes`, pod scheduling, GPU worker join) happens on flannel.
- A follow-up task will drain/replace flannel with Cilium before real workloads (Ollama, Open WebUI, n8n) are deployed, since network-policy behavior should be established before app traffic depends on it.
- Documentation and portfolio narrative should describe this as a deliberate two-step CNI path, not treat flannel as the final choice.

## Follow-ups

- [ ] Validate `k3s` cluster health with `kubectl get nodes` on flannel
- [ ] Install Cilium and migrate the cluster off flannel
- [ ] Validate pod-to-pod networking and any network policies post-migration
- [ ] Update this ADR's Status to note migration completion, or file a follow-up ADR if the Cilium migration surfaces new decisions
