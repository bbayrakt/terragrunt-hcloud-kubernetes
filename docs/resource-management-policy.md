---
date: 2026-08-01
topic: resource-management-policy
---

# Resource Requests, Limits, and Autoscaling Policy (Reference)

This is the durable, reusable policy referenced by `apps/README.md` and `platform/README.md` for
every current and future Helm chart wrapper in this repo. It exists so a new `apps/` or
`platform/` chart can follow a sensible resource footprint from day one instead of shipping with
no bounds at all -- see
[docs/plans/2026-08-01-002-feat-helm-chart-resource-management-plan.md](plans/2026-08-01-002-feat-helm-chart-resource-management-plan.md)
(origin requirements:
[docs/brainstorms/helm-chart-resource-management-requirements.md](brainstorms/helm-chart-resource-management-requirements.md))
for the full rationale and the retrofit of `platform/sealed-secrets/`, `platform/arc-systems/`,
and `platform/arc-runners/` that first established it.

## CPU and memory sizing policy

Every container in every `apps/`/`platform/` Helm chart wrapper must set:

- **An explicit CPU request. No CPU limit.** CPU contention degrades performance (throttling)
  rather than crashing a pod, so a limit isn't needed for stability -- and an unset limit avoids
  artificially throttling bursty workloads (e.g. CI job containers) when the node has spare
  capacity.
- **A memory request and a memory limit**, with the limit providing headroom above the request to
  absorb legitimate spikes without an immediate OOM kill. Exceeding a memory limit -- not a CPU
  limit -- is the actual crash risk this policy exists to close.

Use one shared, conservative value set across every environment (not tuned per environment) unless
you have a concrete reason to diverge -- see the origin plan's Key Technical Decisions for why a
shared value is preferred on this repo's mixed fixed-capacity/Karpenter-elastic node pools.

## `emptyDir` sizing policy

Any `emptyDir` volume a chart declares must have an explicit `sizeLimit`. An unsized `emptyDir` can
fill node disk and trigger disk-pressure evictions across the whole node, not just the offending
pod.

If a chart's convenience fields for provisioning a workload's volumes (e.g. a `containerMode`-style
toggle) are documented as mutually exclusive with per-volume customization, prefer hand-authoring
the full pod spec (copying the chart's own documented blueprint as a starting point) over dropping
the sizing requirement. Record which upstream chart version the blueprint was copied from in a
comment, and re-diff it against the chart's own reference spec on every future version bump.

## VPA (Vertical Pod Autoscaler) -- recommender-only usage

`platform/vpa/` installs the official `kubernetes/autoscaler` Helm chart with the Updater and
admission-controller components disabled -- only the Recommender runs, so no requests/limits are
ever auto-applied and no pod is ever auto-restarted. To add VPA coverage for a new workload:

1. Add a static `VerticalPodAutoscaler` object to that workload's **own** chart directory (e.g.
   `platform/<app>/templates/vpa.yaml`), following
   `platform/sealed-secrets/templates/vpa.yaml`/`platform/arc-systems/templates/vpa.yaml` as a
   template. Do **not** centralize it under `platform/vpa/` -- VPA's `targetRef` requires
   same-namespace with its target, and each workload lives in a different namespace.
2. Set `spec.updatePolicy.updateMode: "Off"` -- the zero-mutation, recommendation-only mode. Do not
   use `Auto` (deprecated) or any mode other than `Off` unless you have deliberately decided to move
   beyond recommendation-only.
3. Set `spec.resourcePolicy.containerPolicies[].controlledValues: RequestsOnly` so recommendations
   stay consistent with this policy's CPU-request-only stance -- without it, VPA's API default
   (`RequestsAndLimits`) will also surface a CPU-limit suggestion this policy deliberately omits.
4. Do not set an explicit `metadata.namespace` on the CR -- it inherits its own Application's
   already-whitelisted destination namespace at apply time.

**Caveat -- not every workload can be targeted.** VPA's `targetRef` mechanism only resolves pods
for well-known controller kinds (`Deployment`, `ReplicaSet`, `StatefulSet`, etc.) or a custom
resource that implements the `/scale` subresource. `platform/arc-runners/` is a concrete example of
a workload that cannot be targeted: its actual runner pods are managed by an `AutoscalingRunnerSet`
CRD with no Deployment/ReplicaSet lineage and no `/scale` subresource, so a VPA object pointed at it
would silently sit with an empty `.status.recommendation` forever. Before adding a VPA object for a
new workload, confirm (e.g. via `helm template`) that it actually resolves to a Deployment,
ReplicaSet, StatefulSet, or scale-subresource-backed object. If it doesn't, that workload's
resources must be tuned manually/observationally instead -- there is no automated substitute today.

**Known upstream limitation:** the VPA chart's own README states Helm cannot upgrade
`CustomResourceDefinition`s in its `crds/` folder on `helm upgrade` -- a native Helm limitation, not
specific to this chart. ArgoCD's Helm rendering re-renders the CRD from the chart on every sync
(not a native `helm upgrade`), which should sidestep this, but verify live at the first VPA chart
version bump; if the CRD schema doesn't update, apply it manually with `kubectl apply
--server-side`.

## Autoscaling decision criteria (KEDA / HPA / VPA)

When adding a new workload, decide its autoscaling treatment using this order:

| Situation | Use |
|---|---|
| Singleton controller with no meaningful load variation (e.g. an operator, a secrets controller) | **No autoscaling.** Right-size once via VPA recommendations (if targetable) and move on. |
| Stateless app whose load varies with steady-state CPU/memory pressure | **Standard HPA**, driven by `metrics-server` (already enabled cluster-wide). |
| Workload that scales on an external event signal -- queue depth, a cron schedule, a custom metric, or needs scale-to-zero | **KEDA.** Do not install KEDA speculatively for a hypothetical future workload -- it adds cluster-scoped RBAC surface and an idle footprint with no benefit until a concrete trigger exists. Install it only when a real workload needs it. |
| Any workload, regardless of the above, where you want a continuously-updated sizing signal without changing replica count | **VPA (recommender-only)**, if the workload is targetable (see caveat above). |
| A workload with its own built-in scaler (e.g. `gha-runner-scale-set`'s `minRunners`/`maxRunners`) | **Use the chart's native scaler.** Don't layer HPA/KEDA on top of a workload that already manages its own scale. |

## Operator runbook: a CI job (or any pod) gets OOM-killed

There is no alerting for this yet (Prometheus/Grafana is planned separately). Until it lands,
triage manually:

1. `kubectl get pod <pod> -n <namespace> -o jsonpath='{.status.containerStatuses[*].lastState.terminated.reason}'`
   -- look for `OOMKilled`.
2. `kubectl describe pod <pod> -n <namespace>` -- check the container's `resources.limits.memory`
   against what the workload actually needed for that run.
3. If the limit is genuinely too low for legitimate use (not a runaway process), raise the memory
   request/limit in that chart's `values.yaml` via a normal Git commit -- see the rollback note
   below for why a live `kubectl edit` will not stick.
4. If VPA is targeting that workload, check `kubectl describe vpa <name> -n <namespace>` for its
   `.status.recommendation` as a data point before picking a new value.

## Rollback note

If a bad resource value causes `CrashLoopBackOff` or repeated OOM kills, **revert the offending Git
commit** -- do not `kubectl edit` the live object. The `platform` `ApplicationSet`'s
`sync_policy.automated.self_heal` will silently reapply the Git-committed value on the next
reconcile loop, overwriting any live edit.
