# ADR 0004: Kubernetes + Local ML Baseline Before a Full Spark Stack

**Status:** Accepted
**Date:** 2026-08-18

## Context

The homelab is being designed as a small, self-hosted AI and platform environment, not as a full distributed data engineering platform from day one. The immediate goal is to establish a working Kubernetes cluster, a dedicated GPU worker, and a usable local ML stack that can host workloads like Ollama, Open WebUI, automation tooling, and agent-based workflows.

The project is intentionally incremental and low-risk. This means the first milestone is the platform foundation: cluster bootstrap, networking, GPU scheduling, and local model serving. Only after that foundation is stable do we expand into heavier data or platform services.

## Decision

Start with Kubernetes and local ML workloads as the base platform. Defer a full distributed data-processing stack such as Spark until the cluster and AI foundation are proven and a real workload demands it.

The project will treat Spark as a future workload running on Kubernetes, not as the initial platform baseline.

## Rationale

- The project follows an incremental design philosophy: start small, validate early, and add complexity only when a real need emerges.
- The current hardware and project goals align better with local AI serving and automation than with a full distributed data stack.
- A small Kubernetes cluster provides the right foundation for future growth across apps, agents, data tooling, and ML workloads.
- A Spark-heavy stack adds lifecycle, storage, networking, and operational overhead before the platform is stable.
- The cluster and GPU node are the real enabling technologies for the portfolio story; the distributed data stack is a later expansion path, not the first milestone.

## Consequences

- The project will prioritize cluster readiness, CNI setup, GPU support, and local model serving before distributed data-platform concerns.
- The platform remains easier to operate and easier to document in portfolio terms.
- Future workloads such as Spark can be added later as a Kubernetes-native workload when there is a concrete use case.
- This keeps the homelab focused on the current phase while preserving a clear road to more advanced platform work.

## Future decision path

When the project reaches a point where distributed data processing is a real requirement, we will add a dedicated ADR for a Spark-on-Kubernetes design. That future decision will cover:
- whether Spark belongs on the current cluster
- what storage and orchestration components are required
- how data locality and job scheduling should be handled
- whether Spark is the right fit compared with other distributed processing options

The central principle remains: Spark is not the starting point; it is a workload that may be added on top of the Kubernetes foundation once the platform is mature.
