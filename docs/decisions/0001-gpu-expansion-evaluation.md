# ADR 0001: GPU Expansion — Used Hardware Evaluation

**Status:** Superseded by [ADR 0002](0002-gpu-and-control-plane-node-purchase.md)
**Date:** 2026-08-16

## Context

Compute baseline is a Dell G5 with a GTX 1060. To scale local AI workloads (LLM serving, GPU scheduling), additional GPU capacity is being evaluated. Design philosophy: start small, scale incrementally — buy for current-phase needs, not anticipated future load.

## Options considered

1. **Standalone RTX 4070 Ti Super 16GB (~$800)** — fairly priced, strong warranty documentation. Fits the incremental-scaling philosophy: adds GPU capacity to an existing node rather than replacing the whole system. Lower risk.
2. **Used prebuilt — Ryzen 7 7800X3D, RTX 4070 Super 12GB, 32GB RAM (~$1,500)** — overpriced relative to fair value (~$1,000–$1,150 estimated from retail comparables). Listing also had a GPU naming typo, a red flag on listing accuracy.
3. **RTX 5070 Ti, Ryzen 7 7800X, 128GB DDR5 (higher-end system)** — capability exceeds current phase needs. Purchase deferred until actual workload bottlenecks (not hypothetical ones) justify it.

## Decision

No purchase yet. Standalone GPU (option 1 pattern) is the preferred shape of purchase when the time comes — lower risk than a prebuilt, and preserves the existing Dell G5 as the base system.

## Evaluation criteria used

- Standalone GPU > prebuilt when an existing compute node is available.
- Red flags on used listings: spec/naming typos, no warranty documentation, no seller account history, PSU/cooling not rated for 24/7 server use.
- Price anchored against new retail comparables and current component shortage context.

## Next trigger

Revisit when a concrete workload bottleneck (VRAM, throughput, concurrent model load) is observed on the current hardware — not before.
