# ADR 0006: Spark-on-Kubernetes Follow-up Decision

**Status:** Accepted
**Date:** 2026-08-18
**Related to:** [ADR 0004](0004-kubernetes-first-local-ml.md)

## Context

The homelab is being built as a small, self-hosted AI and platform environment. The initial decision was to start with Kubernetes and local ML workloads as the foundation, not a full distributed data engineering stack.

This ADR is a follow-up decision for the later stage when distributed data processing becomes a real requirement. It does not change the platform baseline; it describes the path for adding Spark as a workload on top of the Kubernetes cluster once that need is justified.

## Decision

Start with Kubernetes and local ML workloads as the base platform. Defer a full distributed data-processing stack such as Spark until there is a concrete workload that requires it.

If Spark is needed later, it should be added as a workload running on Kubernetes rather than as the initial platform foundation.

## Rationale

- The project follows an incremental design philosophy: prove the foundation first, then add complexity when real demand justifies it.
- Kubernetes is the common substrate for modern data, ML, and app workloads. It gives a clean path to add future systems without redesigning the base platform.
- The immediate hardware and project goals are closer to local ML serving and automation than to distributed analytics. The GPU worker node and small cluster topology are better matched to a local AI baseline.
- Spark introduces additional requirements around scheduling, storage, networking, and operational overhead that are not needed to establish a stable cluster and local model-serving layer.
- This keeps the project lean enough to deliver a working platform quickly while still preserving a path to more advanced data-processing use cases later.

## Consequences

- The project will prioritize cluster bootstrap, networking, GPU readiness, and local ML serving before distributed data-platform concerns.
- Spark or similar large-scale processing tools can be added later as a Kubernetes workload when there is a demonstrated need.
- The platform remains easier to operate and easier to explain in portfolio terms while still supporting future growth.
- The repo will maintain a clean architecture story: foundation first, then platform expansion.

## Future decision path

When a real need emerges for distributed data processing, the project will revisit the design with a dedicated ADR for a Spark-on-Kubernetes path.

That future decision will likely cover:
- whether Spark should run on the existing Kubernetes cluster
- whether additional storage and orchestration components are required
- how data locality and job scheduling should be handled
- whether the workload is better served by Spark, Flink, or another distributed engine

The key point is that Spark is not a replacement for the Kubernetes platform; it is a workload that can be deployed on top of it once the base system is mature.
