---
date: 2026-08-01
topic: helm-chart-resource-management
---

# Resource Requests, Limits, and Autoscaling Policy for Helm Charts

## Problem Frame

None of the three Helm charts currently deployed to the cluster (`platform/sealed-secrets/`,
`platform/arc-systems/`, `platform/arc-runners/`) set explicit CPU/memory requests or limits —
verified by reading each `values.yaml` directly. `arc-runners` also has no `containerMode` set, so
its runner pods' ephemeral storage (`emptyDir` volumes) is undetermined and unsized. On a small,
resource-constrained cluster (production: 3×`cx33` workers, 4 vCPU/8GB each, no elastic node
provisioning; staging: 1×`cpx22` worker, 2 vCPU/4GB, backed by Karpenter) this is a genuine
stability risk: an unbounded pod can starve node capacity, trigger OOM kills, or fill node disk via
an unsized `emptyDir`, with no scheduling or eviction protection in place today.

Beyond fixing the three existing charts, `apps/` and `platform/` are the two tiers every future app
in this repo will be added to (per the two-tier GitOps convention documented in
`docs/brainstorms/argocd-gitops-migration-requirements.md`). Without a documented resource policy,
each new chart risks repeating the same gap. This brainstorm's second half establishes that policy
so future charts inherit sensible defaults instead of re-deriving them.

---

## Requirements

**CPU and memory sizing policy**
- R1. Every container in every `apps/`/`platform/` Helm chart wrapper sets an explicit CPU
  *request*. No CPU *limit* is set, since CPU contention degrades performance (throttling) rather
  than crashing a pod, and an unset limit avoids artificially throttling bursty workloads (e.g.
  `arc-runners`' CI job containers) when the node has spare CPU.
- R2. Every container sets both a memory *request* and a memory *limit*, with the limit providing
  headroom above the request to absorb legitimate spikes without immediately OOM-killing the pod,
  since exceeding a memory limit is the actual crash risk this work exists to close.
- R3. One shared, conservative value set is used across both staging and production for each
  component — not separately tuned per environment.

**Ephemeral storage (`emptyDir`) policy**
- R4. Any `emptyDir` volume declared by a chart has an explicit `sizeLimit` set. (Verified: no
  `emptyDir` volume is explicitly declared anywhere in this repo's own manifests today — this
  requirement governs both the `arc-runners` retrofit below and any future chart.)
- R5. `arc-runners`' `containerMode` is set explicitly to `dind` (replacing today's unset/implicit
  chart default), and `sizeLimit` is set on all three `emptyDir` volumes that mode creates (`work`,
  `dind-sock`, `dind-externals`).

**Continuous right-sizing (VPA)**
- R6. A Vertical Pod Autoscaler (VPA) installation is added as a new `platform`-tier chart, running
  in **recommender-only mode** — the Recommender component only; the Updater and
  admission-controller components are not deployed, so no requests/limits are ever auto-applied and
  no pod is ever auto-restarted.
- R7. A `VerticalPodAutoscaler` object (in `Off`/recommend-only update mode) targets each of the
  three existing workloads (`sealed-secrets`, `arc-systems`, `arc-runners`) so recommendation data
  begins accumulating from day one, independent of and prior to the separately-planned
  Prometheus/Grafana observability stack.

**Autoscaling decision criteria (KEDA / HPA)**
- R8. KEDA is not installed as part of this work. None of the three existing charts is a valid
  trigger target: `arc-runners` already has its own GitHub-job-driven scaler (`minRunners`/
  `maxRunners`) built into the chart; `sealed-secrets` and `arc-systems` are singleton controllers
  with no queue/event signal to scale on.
- R9. The policy (see R13) documents explicit decision criteria for future apps, distinguishing
  four outcomes: no autoscaling (singleton/controller-style workloads), standard HPA (steady-state
  CPU/memory-driven scaling of a stateless app), KEDA (event/queue/schedule-driven scaling,
  including scale-to-zero), and VPA-only (right-sizing without changing replica count).

**Existing chart retrofits**
- R10. `platform/sealed-secrets/values.yaml` sets explicit `resources.requests`/`resources.limits`
  per R1/R2, replacing reliance on the upstream Bitnami chart's implicit `resourcesPreset: "nano"`
  default (verified in the chart's own `values.yaml`).
- R11. `platform/arc-systems/values.yaml` sets explicit resource requests/limits per R1/R2 for the
  `gha-runner-scale-set-controller` container(s).
- R12. `platform/arc-runners/values.yaml` sets `containerMode.type: dind` (R5), resource
  requests/limits per R1/R2 for both the runner and `dind` containers, and `sizeLimit` on all three
  `emptyDir` volumes.

**Documented convention for future charts**
- R13. A durable convention doc captures the CPU/memory policy (R1-R3), the `emptyDir` policy
  (R4), VPA recommender-only usage (R6-R7), and the KEDA/HPA/VPA decision criteria (R9), so a future
  contributor adding a chart under `apps/` or `platform/` can follow it directly.
- R14. `apps/README.md` and `platform/README.md` are updated to reference the new convention doc,
  consistent with how they already reference `docs/gitops-repo-scaffold.md`.

---

## Key Flows

- F1. Retrofit an existing `platform`-tier chart with the resource policy
  - **Trigger:** This effort's initial rollout.
  - **Steps:** For each of the three charts, determine sensible request/limit values (CPU request
    only, memory request + limit) → for `arc-runners`, additionally set `containerMode: dind` and
    size its three `emptyDir` volumes → add a matching `VerticalPodAutoscaler` object in
    recommender-only mode → commit to the GitOps repo, let ArgoCD sync.
  - **Outcome:** All three charts run with explicit requests/limits and sized `emptyDir` volumes;
    VPA recommendation data starts accumulating immediately.
  - **Covered by:** R1, R2, R3, R5, R6, R7, R10, R11, R12

- F2. Add a new `apps/` or `platform/` chart going forward
  - **Trigger:** An operator adds a new Helm chart wrapper to either tier.
  - **Steps:** Consult the resource-policy doc → set a CPU request (no limit) and a memory
    request + limit for every container → set an explicit `sizeLimit` on any `emptyDir` volume →
    decide autoscaling per the documented criteria (none / HPA / KEDA) → optionally add a
    recommender-only `VerticalPodAutoscaler` object.
  - **Outcome:** New chart ships with a sensible resource footprint and an explicit autoscaling
    decision from day one, instead of silently inheriting no limits at all.
  - **Covered by:** R9, R13, R14

---

## Chart-by-chart summary

| Chart | CPU | Memory | `emptyDir` | Autoscaling |
|---|---|---|---|---|
| `sealed-secrets` | request only | request + limit | none | none (singleton controller) |
| `arc-systems` | request only | request + limit | none | none (singleton controller) |
| `arc-runners` | request only | request + limit | `work`, `dind-sock`, `dind-externals` (all sized) | own built-in GH-job scaler; no HPA/KEDA |

---

## Success Criteria

- No pod under `apps/` or `platform/` ships without an explicit CPU request and an explicit memory
  request + limit — verifiable by reading each chart's `values.yaml` or running `helm template`.
- The three existing charts no longer risk starving node capacity, triggering unbounded OOM kills,
  or filling node disk via an unsized `emptyDir`.
- VPA recommender data is available (`kubectl describe vpa ...`) for all three existing workloads
  from shortly after rollout, giving a concrete, data-driven basis for future tuning — including
  once Prometheus/Grafana is installed.
- A future contributor adding a new chart can follow the documented policy and decision criteria
  without re-deriving CPU/memory/`emptyDir`/autoscaling choices from scratch.

---

## Scope Boundaries

- Installing Prometheus/Grafana is out of scope here — planned separately; this work does not
  depend on it and VPA's recommender does not require it (it uses `metrics-server`).
- Installing KEDA is out of scope; only the documented decision criteria for future use (R9) is in
  scope.
- VPA's Updater and admission-controller components (auto-apply / auto-restart mode) are explicitly
  out of scope — recommender-only, per R6.
- Per-environment (staging vs. production) differentiated sizing is out of scope; one shared,
  conservative value set is used per R3.
- Standard HPA is not being added for any of the three existing charts, since none is a valid
  target today (per R8); HPA only enters scope for a future app matching the R9 criteria.
- Exact numeric CPU/memory request/limit values and `emptyDir` `sizeLimit` values are not finalized
  in this document — deferred to planning (see Outstanding Questions).

---

## Key Decisions

- **CPU: request-only, no limit.** Avoids artificially throttling bursty workloads (especially
  `arc-runners`' CI job containers) when the node has spare CPU; CPU contention degrades
  performance rather than crashing a pod, so a limit isn't needed for the stability goal this work
  is about.
- **Memory: request + limit everywhere.** Matches the original ask directly — OOM-kill risk from
  unbounded memory use is the primary cluster-stability concern motivating this work.
- **VPA in recommender-only mode, installed now even though Prometheus/Grafana is planned later.**
  VPA's recommender keeps its own usage history via `metrics-server` independent of Prometheus; it
  automates the specific "what should this container request" analysis rather than requiring manual
  dashboard review, and recommender-only mode carries no auto-restart risk.
- **KEDA deferred, not installed speculatively.** None of the three existing charts is a valid
  target, and installing it with no current use adds cluster-scoped RBAC surface (relevant given
  this repo's already-deliberate `apps`/`platform` RBAC boundary) and idle footprint on a
  resource-tight cluster for no near-term benefit. Install it when a concrete triggering app exists.
- **Shared (not per-environment) sizing.** Staging's Karpenter integration (verified: real and
  configured, capped at 16 vCPU across several node types) gives it an elastic safety valve if a
  shared value runs tight there. Production has no such valve today (verified: its
  `karpenter`/`karpenter-helm` directories are empty placeholders, not live stacks) and is a fixed
  3-node pool — the environment the shared conservative value is calibrated to protect.
- **`arc-runners` `containerMode: dind`**, replacing today's implicit/unset default, so its
  `emptyDir` volumes are concrete and sizeable rather than left to chart-default ambiguity.

---

## Dependencies / Assumptions

- Assumes `arc-runners`' CI jobs need Docker-in-Docker rather than a Kubernetes-mode
  sibling-container or no-volume execution model — this was decided in dialogue but not verified
  against actual GitHub Actions workflow files in this repo; flagged below for a planning-time
  double-check before implementation.
- Assumes `metrics-server` (already enabled by default in the Terraform `kubernetes-cluster`
  module) stays enabled, since VPA's recommender depends on it for usage data.
- Assumes production's Karpenter stack (currently empty placeholder directories) is not activated
  as part of this work. If it is added later, the "shared conservative value, calibrated to
  production's fixed capacity" rationale should be revisited.
- Assumes the separately-planned Prometheus/Grafana installation is a later, independent effort;
  this work does not block on it and is not superseded by it.

---

## Outstanding Questions

### Deferred to Planning

- [Affects R12][Needs research] Confirm via actual GitHub Actions workflow files (or observed job
  history) that `arc-runners` CI jobs genuinely need Docker-in-Docker, rather than fitting
  `kubernetes` or `kubernetes-novolume` container mode better.
- [Affects R10, R11, R12][Needs research] Determine exact numeric CPU request, memory
  request/limit, and `emptyDir` `sizeLimit` values for each container — informed by upstream chart
  guidance, typical GitHub Actions self-hosted runner resource profiles, and this cluster's node
  sizes (`cx33` production / `cpx22` staging). This document intentionally leaves exact numbers
  unset.
- [Affects R6, R7][Technical] Confirm the exact manifest/Helm-chart approach for installing VPA with
  only the Recommender component (excluding Updater/admission-controller), the chart/version to use,
  and where it lives in the `platform` tier (RBAC needs, any cluster-scoped kinds to whitelist in
  the `platform` `AppProject`).
- [Affects R13, R14][Technical] Decide the exact filename/location for the new convention doc (e.g.
  alongside `docs/gitops-repo-scaffold.md`) during planning.

---

## Next Steps

-> `/ce-plan` for structured implementation planning
