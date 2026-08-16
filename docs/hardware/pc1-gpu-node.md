# PC 1 — GPU Node

Dedicated GPU workload node. See [ADR 0002](../decisions/0002-gpu-and-control-plane-node-purchase.md).

## Specs

| Field | Value |
|---|---|
| CPU | AMD Ryzen 7 5700G w/ Radeon Graphics (16 threads) |
| GPU | NVIDIA GeForce RTX 5060 Ti (16GB VRAM) |
| RAM | 32GB DDR4 |
| Storage | 512GB SSD |
| Purchase price | ~$800 |
| OS | Ubuntu Server (planned) |
| Hostname | _TBD_ |
| Static IP | _TBD_ |

## Bootstrap log

| Date | Change | Notes |
|---|---|---|
| | | |

## Role in cluster

Kubernetes GPU-scheduled worker node — Ollama inference and other GPU-bound ML workloads.
