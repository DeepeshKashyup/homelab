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
| OS | Ubuntu 26.04 LTS |
| Hostname | `gpu-node-01` |
| MAC | `d8:5e:d3:05:3e:af` (enp6s0) |
| DHCP IP (pre-reservation) | `192.168.0.79` |
| Static IP | _pending router reservation — suggested `192.168.0.101`, or keep `.79`_ |
| NVIDIA driver | 595.84, CUDA 13.2 (confirmed via `nvidia-smi`) |

## Bootstrap log

| Date | Change | Notes |
|---|---|---|
| 2026-08-16 | Confirmed OS, NVIDIA driver, network identity | SSH not yet installed |

## Role in cluster

Kubernetes GPU-scheduled worker node — Ollama inference and other GPU-bound ML workloads.
