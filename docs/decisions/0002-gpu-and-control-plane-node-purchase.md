# ADR 0002: GPU + Control-Plane Node Purchase

**Status:** Decided — purchased
**Date:** 2026-08-16
**Supersedes:** [ADR 0001](0001-gpu-expansion-evaluation.md)

## Context

ADR 0001 evaluated adding a standalone GPU to the existing Dell G5. Instead, two separate machines were acquired, splitting GPU workload capacity from the app/control-plane role rather than combining them on one box.

## Decision

Purchased two nodes:

1. **PC 1 — GPU workload node (~$800)**
   AMD Ryzen 7 5700G w/ Radeon Graphics (16 threads), 32GB DDR4 RAM, 512GB SSD, NVIDIA GeForce RTX 5060 Ti (16GB VRAM).
   Role: GPU-scheduled Kubernetes worker — Ollama inference and other GPU-bound workloads.

2. **PC 2 — HP ProDesk G5 800**
   Intel i5, 32GB DDR4 RAM, 1TB SSD.
   Role: Kubernetes control plane + general app workloads (kept off the GPU box for isolation).

The original **Dell G5 (GTX 1060)** remains in the fleet; its role is TBD (likely repurposed as an additional worker or backup node) now that dedicated GPU and control-plane nodes exist.

## Rationale

- Splitting control plane from GPU workload gives cleaner isolation — control-plane/API-server load doesn't compete with GPU inference, and the GPU node can be rebooted/drained for driver updates without touching the control plane.
- 16GB VRAM on PC 1 gives meaningful headroom over the GTX 1060 baseline for local LLM serving.
- Total spend (~$800 confirmed for PC 1; PC 2 price not recorded) stayed within incremental-scaling intent rather than jumping to the higher-end system considered and deferred in ADR 0001.

## Naming note

PC 2 is an "HP ProDesk **G5** 800" — the "G5" in its model name is coincidental and unrelated to the original **Dell G5** baseline node. Use unambiguous hostnames (e.g. `gpu-node`, `control-plane`, `dell-g5-legacy`) when bootstrapping to avoid confusion between the two.

## Follow-ups

- [ ] Confirm/record PC 2 purchase price
- [ ] Bootstrap both nodes with stable SSH (see `infra/bootstrap/`)
- [ ] Decide final role for the original Dell G5
- [ ] Update `docs/hardware/` inventory once hostnames/IPs are assigned
