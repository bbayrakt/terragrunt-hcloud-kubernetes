---
title: "feat: Helm Chart Resource Requests/Limits Policy + Recommender-Only VPA"
type: feat
status: active
date: 2026-08-01
deepened: 2026-08-01
origin: docs/brainstorms/helm-chart-resource-management-requirements.md
---

# Helm Chart Resource Requests/Limits Policy + Recommender-Only VPA

## Overview

Set explicit CPU requests (no CPU limit), memory requests+limits, and sized `emptyDir` volumes on
the three existing `platform`-tier Helm charts (`sealed-secrets`, `arc-systems`, `arc-runners`),
add a new `platform/vpa/` chart running the Vertical Pod Autoscaler Recommender only (never
auto-applying or auto-restarting anything), and document a reusable convention so future
`apps/`/`platform/` charts inherit this policy instead of shipping with no resource bounds at all.

---

## Problem Frame

None of the three charts currently deployed sets explicit CPU/memory requests or limits (verified
directly from each `values.yaml`), and `arc-runners` has no `containerMode` set, leaving its
runner pods' ephemeral storage undetermined. On a small cluster (production: 3×`cx33`, fixed pool,
no elastic provisioning; staging: 1×`cpx22` + Karpenter, capped 16 vCPU) this risks OOM kills,
node-capacity starvation, and disk-pressure evictions from unsized `emptyDir` volumes, with no
protection in place today. See the origin document's Problem Frame for full detail.

**Scoping correction found during planning:** production runs none of these three workloads by
any mechanism today — no `infra/environments/production/argocd-gitops/` stack exists, and none of
`gha-runner-scale-set(-controller)`/`sealed-secrets` appear in production's `helm_charts` map
either (verified by reading `infra/environments/production/env.hcl` in full and grepping the whole
`production/` tree). This plan's changes are authored once in the shared GitOps repo content (per
R3's "one shared value set"), but **only actually sync and run on staging** until production gets
its own `argocd-gitops` stack — a separate, out-of-scope future effort (see Scope Boundaries).

---

## Requirements Trace

**Resource sizing policy (R1-R4)**
- R1. Every container sets an explicit CPU request; no CPU limit is set.
- R2. Every container sets a memory request and a memory limit with headroom above the request.
- R3. One shared, conservative value set is used across staging and production (not tuned per
  environment).
- R4. Any `emptyDir` volume has an explicit `sizeLimit`.

**`arc-runners` `dind` shape (R5)**
- R5. `arc-runners` runs in `dind` mode with sized `emptyDir` volumes for `work`, `dind-sock`,
  `dind-externals`. **Shape correction (see Key Technical Decisions):** the chart's convenience
  `containerMode.type: dind` field and per-volume `sizeLimit` customization are documented upstream
  as mutually exclusive — this plan hand-authors the full `dind` pod spec (copying the chart's own
  documented blueprint) with `sizeLimit` added, rather than setting `containerMode.type: dind`
  literally, to honor R5's intent. **Unresolved premise, elevated from the origin document's own
  flagged research item (see Open Questions):** whether `arc-runners`' CI jobs genuinely need
  Docker-in-Docker at all — versus a `kubernetes`/`kubernetes-novolume` mode that needs no
  privileged container — was never actually checked against real workflow files, in the origin
  brainstorm or during this planning pass. R5 as scoped assumes `dind` is correct; this must be
  confirmed (or the mode changed) before U3 is implemented.

**VPA (R6-R7)**
- R6. A VPA installation runs in recommender-only mode (no Updater, no admission-controller).
- R7. A `VerticalPodAutoscaler` object (recommendation-only) targets each existing workload that
  VPA can actually resolve. **Placement correction (see Key Technical Decisions):** VPA's
  `targetRef` requires same-namespace with its target, so each CR is co-located as a static
  template inside its own target's existing chart directory, not centralized under
  `platform/vpa/`. **Coverage correction, found during document review (see Key Technical
  Decisions):** `arc-runners` is excluded from per-workload VPA coverage — its runner workload has
  no Deployment/ReplicaSet (or scale-subresource CRD) lineage for VPA's `targetRef` to resolve, so
  R7 now covers `sealed-secrets` and `arc-systems` only.

**Autoscaling decision criteria (R8-R9)**
- R8. KEDA is not installed; none of the three charts is a valid trigger target.
- R9. The convention doc documents decision criteria distinguishing no-autoscaling / HPA / KEDA /
  VPA-only outcomes for future apps.

**Chart retrofits (R10-R12)**
- R10, R11, R12. Existing-chart retrofits for `sealed-secrets`, `arc-systems`, `arc-runners`
  respectively.

**Documentation (R13-R14)**
- R13, R14. New convention doc + `apps/README.md`/`platform/README.md` references.

**Origin flows:** F1 (retrofit existing charts), F2 (add a new `apps`/`platform` chart going
forward) — both carried forward; F1's steps are refined per the R5/R7 corrections above.

---

## Scope Boundaries

- Installing Prometheus/Grafana is out of scope (planned separately).
- Installing KEDA is out of scope; only R9's decision criteria are documented.
- VPA's Updater and admission-controller components are out of scope — recommender-only, per R6.
- Per-environment differentiated sizing is out of scope; one shared value set is used per R3.
- Standard HPA is not added for any of the three existing charts (none is a valid target today).
- `arc-runners` is excluded from per-workload VPA coverage (R7) — found during document review
  that its ephemeral, controller-managed runner pods have no VPA-resolvable target (no Deployment/
  ReplicaSet/`/scale`-subresource lineage); its resource values rely on manual tuning instead, not
  VPA recommendation data.
- The exact numeric values proposed in this plan (see Key Technical Decisions) are a grounded
  starting point, not a final tuned answer — validating and refining them against real VPA
  recommendation data (and, later, Prometheus/Grafana) is intentionally left as follow-up.

### Deferred to Follow-Up Work

- Production's own `argocd-gitops` Terragrunt stack, and this content's actual rollout to
  production: separate future effort, not part of this plan.
- Post-launch numeric tuning informed by live VPA recommender data: future iteration, once enough
  usage history has accumulated on staging.
- Confirming whether ArgoCD's Helm rendering fully sidesteps the VPA chart's vendor-documented
  "Helm cannot upgrade CRDs in `crds/`" limitation: only observable at the first VPA chart version
  bump, not resolvable statically now.
- **Node isolation for `arc-runners`** (user-confirmed during document review, decided in lieu of
  accepting the privileged `dind` container's node-compromise exposure as-is): dedicate
  `arc-runners` to a tainted node pool so a container escape from the shared `dind-sock` cannot
  reach co-located workloads. Scoped as a separate follow-up plan/unit, not part of this plan's
  U1-U8, because it touches cluster-level node provisioning rather than GitOps chart content:
  staging can likely use Karpenter's existing `nodepool_spec_overrides` extension point (already
  documented in `infra/modules/karpenter/variables.tf` as supporting taints); production has no
  Karpenter today (per this plan's own Problem Frame correction) and would need its own
  `worker_nodepools` taint/label addition instead. Either way, `platform/arc-runners/values.yaml`
  would also need a matching `nodeSelector`/toleration added once the tainted pool exists — that
  follow-on edit is a natural continuation of this plan's U3, not a full redesign.

---

## Context & Research

### Relevant Code and Patterns

- `platform/arc-runners/Chart.yaml` / `values.yaml` — the exact thin-wrapper-chart pattern
  (`Chart.yaml` with one `dependencies` entry pinning the upstream chart; `values.yaml` nesting
  values under the dependency's alias key) that `platform/vpa/` must follow.
- `platform/arc-runners/templates/sealed-secret.yaml` — the established pattern for adding a
  static, non-chart-generated manifest inside a wrapper chart's `templates/` directory; this is
  reused for the per-workload `VerticalPodAutoscaler` CR objects (R7).
- `infra/modules/argocd-gitops/variables.tf` — `platform_destination_namespaces` (namespace
  allow-list, currently `["arc-systems", "sealed-secrets", "arc-runners"]`) and
  `platform_cluster_resource_whitelist` (cluster-scoped kind allow-list, already covering
  `CustomResourceDefinition`, `ClusterRole`, `ClusterRoleBinding`, `Namespace` — everything a
  recommender-only VPA install needs, no whitelist change expected).
- `infra/modules/argocd-gitops/main.tf` — confirms `ServerSideApply=true` and
  `preserve_resources_on_deletion=true` already apply to the whole `platform` `ApplicationSet`
  (inherited automatically by any new `platform/*` directory, including `vpa`).
- `docs/gitops-repo-scaffold.md` — reference-doc frontmatter/structure convention (flat file under
  `docs/`, `date:`/`topic:` frontmatter, opening paragraph naming origin plan/brainstorm) to mirror
  for the new resource-management convention doc.
- `apps/README.md` / `platform/README.md` — both already end with a sentence referencing
  `docs/gitops-repo-scaffold.md` followed by one referencing the migration-requirements brainstorm;
  R14 adds a third sentence in the same spot.

### Institutional Learnings

- `docs/solutions/architecture-patterns/argocd-two-tier-rbac-boundary-and-arc-onboarding-2026-08-02.md`
  — the load-bearing rule that any app needing RBAC-object or cluster-scoped creation rights
  belongs in `platform/`, never `apps/`; confirms VPA's Recommender (ClusterRole/ClusterRoleBinding
  + CRD) belongs in `platform/`. Also documents the `CreateNamespace=true` whitelist requirement and
  the `ServerSideApply=true` / large-CRD-annotation-limit precedent, both already satisfied for the
  `platform` tier.
- `docs/solutions/architecture-patterns/self-hosted-gitops-monorepo-migration-terragrunt-sops-state-preservation-2026-08-01.md`
  — the `kubernetes_manifest` CRD+CR chicken-and-egg limitation in Terraform. Avoided entirely here
  by routing the VPA CRD and the per-workload CR objects through ArgoCD/Helm rendering (as GitOps
  content), not Terraform `kubernetes_manifest`.
- `docs/plans/2026-07-30-001-feat-argocd-gitops-migration-plan.md` (verified live, ~lines 439-441)
  — confirms `platform`-tier namespaces carry **no** Pod Security Standard label at all (only
  `apps`-tier gets `restricted` by default), so `arc-runners`' hand-authored `dind` container's
  `privileged: true` requirement is not blocked by this repo's PSA setup — an already-accepted
  condition, not a new blocker.

### External References

- `kubernetes/autoscaler/vertical-pod-autoscaler/docs/components.md`, `installation.md`,
  `api.md` — component list, `updateMode` enum (`Off` is the zero-mutation mode used here),
  Kubernetes-version compatibility (VPA 1.7.x needs 1.28+; this cluster tracks 1.33.0).
- Official Helm chart: `https://kubernetes.github.io/autoscaler`, chart `vertical-pod-autoscaler`
  v0.11.0 (`appVersion: 1.7.1`) — exposes `recommender.enabled`/`updater.enabled`/
  `admissionController.enabled` toggles; its own README states *"not ready for production use"*
  (accepted risk, see Key Technical Decisions) and *"Helm cannot upgrade CustomResourceDefinitions
  in the `crds` folder"* (tracked as a Deferred-to-Follow-Up item).
- `bitnami/charts` `common/templates/_resources.tpl` — `nano` preset
  (`requests: {cpu: 100m, memory: 128Mi}`, `limits: {cpu: 150m, memory: 192Mi}`) used purely as a
  grounded sizing heuristic for the two lightweight controller retrofits (adjusted slightly upward
  since that preset is itself documented as "for basic testing... not meant to be used in
  production"). **Correction found during document review:** this preset mechanism belongs to
  Bitnami's *current* `common` library chart, not the actual pinned `sealed-secrets` chart version
  this repo uses (`2.19.1` from `https://bitnami.github.io/sealed-secrets`, per
  `platform/sealed-secrets/Chart.yaml`) — **verified directly** via `helm show values
  bitnami-sealed-secrets/sealed-secrets --version 2.19.1`, that pinned version has no
  `resourcesPreset` field at all; its `resources` key is simply `{limits: {}, requests: {}}` with
  no default of any kind. The `nano` numbers are used here only as an external sizing reference,
  not as a claim about what the pinned chart currently defaults to (see U1).
- `actions/actions-runner-controller` `gha-runner-scale-set` upstream `values.yaml` — confirms no
  default resources are set, and that `containerMode` convenience fields and hand-authored
  `template.spec` customization are mutually exclusive (drives R5's shape correction).

---

## Key Technical Decisions

- **CPU request-only / memory request+limit, applied uniformly — including to the new VPA chart's
  own Recommender container.** The origin doc's per-chart table only covered the 3 existing
  charts; R1-R3 logically extend to `platform/vpa/` too, closing a self-referential gap the
  planning-phase flow analysis surfaced.
- **VPA chart: official `kubernetes/autoscaler` chart, accepted despite its "not ready for
  production use" disclaimer.** Recommender-only mode plus `updateMode: Off` on every CR means the
  installation can never mutate a running pod even if the chart has rough edges — this bounds the
  blast radius enough to accept the risk rather than switching to a less-official alternative.
  Considered and rejected: Fairwinds' `fairwinds-stable/vpa` (more mature, no disclaimer, but not
  the canonical upstream project) and raw upstream manifests via `vpa-process-yamls.sh` (avoids the
  chart-maturity question entirely, but breaks this repo's established Helm-wrapper-chart
  convention for no added safety, since recommender-only + `Off` mode already bounds risk).
- **`arc-runners` hand-authors its full `dind` pod spec instead of setting `containerMode.type:
  dind`.** The upstream chart documents these as mutually exclusive when any volume customization
  (like `sizeLimit`) is needed. Since sizing `emptyDir` is a direct requirement from the original
  ask, this plan accepts the upgrade-drift cost (future chart version bumps to the reference dind
  blueprint — image tags, env vars, probes — must be manually re-diffed) rather than silently
  dropping the sizing requirement.
- **Per-workload `VerticalPodAutoscaler` CRs are co-located in each target's own chart directory**
  (`platform/sealed-secrets/templates/vpa.yaml`, etc.), not centralized under `platform/vpa/`,
  because VPA's `targetRef` requires same-namespace with its target and each workload lives in a
  different namespace. Each CR manifest omits an explicit `metadata.namespace`, so it inherits its
  own Application's already-whitelisted destination namespace at apply time — no cross-namespace
  concern remains.
- **`arc-runners` is excluded from per-workload VPA coverage (found during document review, R7
  scope correction).** VPA's `targetRef` mechanism only resolves pods for well-known controller
  kinds or a `/scale`-subresource CR. A live `helm template` of the pinned `gha-runner-scale-set`
  chart confirms its only rendered workload object is an `AutoscalingRunnerSet` — no Deployment,
  ReplicaSet, or StatefulSet — which the controller reconciles into ephemeral per-job pods at
  runtime, outside anything Helm renders; neither CRD defines a `/scale` subresource. Targeting it
  anyway would silently produce an empty `.status.recommendation` forever, so U6 covers only
  `sealed-secrets` and `arc-systems`; `arc-runners`' values (U3) rely on manual/observational
  tuning instead (documented as a decision criterion in U7).
- **VPA container policies set `controlledValues: RequestsOnly` (found during document review).**
  VPA's `controlledValues` field defaults to `RequestsAndLimits`, which would surface CPU-limit
  recommendations that directly contradict this plan's own CPU-request-only policy (R1) —
  `RequestsOnly` keeps recommendation output consistent with the policy it's meant to validate.
- **VPA Recommender: `replicas: 1`, Pod Disruption Budget disabled** (upstream chart defaults to 2
  replicas + `minAvailable: 1`). On staging's single static node plus Karpenter-provisioned
  elastic nodes, a 2-replica PDB risks deadlocking a Karpenter drain, and running 2 replicas of a
  non-critical, no-SLA recommendation-only component contradicts this effort's own
  resource-conservation goal.
- **Starting numeric values** (grounded, not guessed — see Context & Research for sourcing):

  | Component | CPU request | Memory request | Memory limit | `emptyDir` sizing |
  |---|---|---|---|---|
  | `sealed-secrets-controller` | `100m` | `128Mi` | `256Mi` | n/a |
  | `gha-runner-scale-set-controller` | `100m` | `128Mi` | `256Mi` | n/a |
  | `arc-runners` runner container | `500m` | `512Mi` | `1536Mi` | n/a (see volumes below) |
  | `arc-runners` `dind` sidecar | `250m` | `256Mi` | `1024Mi` | n/a |
  | `arc-runners` `work` volume | — | — | — | `5Gi` |
  | `arc-runners` `dind-sock` volume | — | — | — | `16Mi` |
  | `arc-runners` `dind-externals` volume | — | — | — | `1Gi` |
  | VPA `recommender` container | `50m` | `500Mi` | `1000Mi` (upstream default kept; CPU limit dropped per policy) | n/a |

  These are deliberately conservative starting points sized to fit staging's smaller `cpx22`
  worker comfortably while leaving headroom on production's `cx33` pool (per R3). Refining
  `sealed-secrets`/`arc-systems` with real VPA recommendation data is explicit follow-up work, not
  this plan's completion bar; `arc-runners`' values have **no** VPA data source (per the exclusion
  above) and must be refined manually from real job history instead.
- **`platform_destination_namespaces` is extended, not overridden per-stack.** Adding `"vpa"` to
  the Terraform module's *default* list (rather than an explicit override in staging's
  `terragrunt.hcl` inputs) means production's future `argocd-gitops` stack inherits it
  automatically — consistent with how the existing three namespaces are handled today.

---

## Open Questions

### Resolved During Planning

- VPA CR placement (same-namespace `targetRef` constraint): co-locate in each target's own chart
  directory — see Key Technical Decisions.
- `containerMode`/`sizeLimit` mutual exclusivity: hand-author the full `dind` pod spec — see Key
  Technical Decisions.
- VPA chart choice given the "not ready for production use" disclaimer: proceed with the official
  chart, given recommender-only mode bounds the blast radius — user-confirmed during planning.
- Recommender replica count / PDB: override to `replicas: 1`, PDB disabled.
- Starting numeric CPU/memory/`emptyDir` values: proposed and grounded per the table above.
- Operator-facing behavior when a CI job's memory usage exceeds the shared limit: documented as an
  interim manual triage runbook in the new convention doc (U7), pending Prometheus/Grafana.
- Whether the VPA chart's rendered manifests introduce any cluster-scoped kind beyond
  `platform_cluster_resource_whitelist`'s existing four entries: **confirmed no** -- a live
  `helm template --include-crds` dry-run of the exact recommender-only configuration (run during
  planning against the pinned chart version) rendered only `CustomResourceDefinition`,
  `ClusterRole`, `ClusterRoleBinding`, `ServiceAccount`, and `Deployment` -- no whitelist change is
  needed, and no `MutatingWebhookConfiguration` leaks in despite `admissionController.enabled:
  false` being a runtime toggle rather than a guaranteed template-omission in every chart (this
  chart correctly omits it entirely from rendered output when disabled).
- Whether `arc-runners` can be targeted by a `VerticalPodAutoscaler` CR: **confirmed no** (found
  during document review) -- a live `helm template` of the pinned `gha-runner-scale-set` chart
  renders only an `AutoscalingRunnerSet` object (no Deployment/ReplicaSet/StatefulSet, no `/scale`
  subresource on either ARC CRD), so R7/U6 now cover `sealed-secrets` and `arc-systems` only — see
  Key Technical Decisions.
- VPA container policies need `controlledValues: RequestsOnly`: added to U6 (found during document
  review) so recommendations stay consistent with the plan's own CPU-request-only policy (R1).
- `dind` mode confirmed genuinely necessary for `arc-runners`' CI jobs (user-confirmed): jobs
  build/run Docker images, so `containerMode.type: dind`'s hand-authored equivalent (per R5's shape
  correction) is the right approach — no mode change needed. This closes the origin brainstorm's
  flagged-but-never-verified research item.
- The privileged `dind` container's node-compromise exposure gets an explicit mitigation
  (user-confirmed): isolate `arc-runners` onto a dedicated, tainted node pool, tracked as a
  follow-up unit (see Scope Boundaries → Deferred to Follow-Up Work) rather than accepting the
  exposure as-is or relying solely on an org-level GitHub Actions policy change.
- `platform/sealed-secrets`'s pinned chart version has no `resourcesPreset` mechanism at all
  (corrected during document review): U1 sets values from a genuinely empty default, not by
  overriding a `"nano"` preset that doesn't exist in the pinned chart version.


### Deferred to Implementation

- Whether ArgoCD's `helm template --include-crds` re-rendering on every sync fully substitutes for
  the VPA chart's vendor-documented "Helm cannot upgrade CRDs" limitation: verify live at first
  sync, and again at the first future VPA chart version bump (if it does not, a manual
  `kubectl apply --server-side` step against the CRD is the fallback).
- Confirm the in-cluster Kubernetes version actually satisfies VPA 1.7.x's 1.28+ floor before
  applying -- low risk (the cluster module's `kube_version` default already references 1.33.0,
  well above the floor), but not directly checkable without live `kubectl` access during planning.

---

## Implementation Units

- [ ] U1. **Retrofit `platform/sealed-secrets` with explicit resources**

**Goal:** Set explicit CPU/memory values on the Sealed Secrets controller — **corrected during
document review:** the pinned chart version (`2.19.1`) has no `resourcesPreset` mechanism at all
(verified via `helm show values bitnami-sealed-secrets/sealed-secrets --version 2.19.1`); its
`resources` key defaults to a genuinely empty `{limits: {}, requests: {}}`, so this unit sets
values from nothing, not from a preset override.

**Requirements:** R1, R2, R3, R10

**Dependencies:** None

**Files:**
- Modify: `platform/sealed-secrets/values.yaml`

**Approach:**
- Set `sealed-secrets.resources.requests.cpu`, `.requests.memory`, `.limits.memory` per the Key
  Technical Decisions table; do not set `resources.limits.cpu`.
- Add an inline comment (matching this repo's comment-density convention) noting the values are a
  starting estimate (using Bitnami's `nano` preset from an unrelated, newer chart purely as an
  external sizing reference point, not as this chart's own default) from the origin brainstorm's
  node-size constraint, to be refined via VPA data.

**Patterns to follow:**
- Existing inline-comment style in `platform/arc-runners/values.yaml`
  (`controllerServiceAccount` block) for explaining *why*, not just *what*.

**Test scenarios:**
- Happy path: `helm template` (via `helm dependency build` + `helm template` against the wrapper
  chart) renders the Sealed Secrets Deployment with the exact requests/limits values set, no CPU
  limit present.
- Integration: after ArgoCD syncs, the running `sealed-secrets-controller` pod's
  `spec.containers[0].resources` matches the declared values (`kubectl get pod ... -o
  jsonpath={.spec.containers[0].resources}`).
- Edge case: confirm the controller does not immediately OOM-kill or CrashLoopBackOff under the
  new memory limit during a normal sealing/unsealing operation.

**Verification:**
- `terragrunt hcl validate` / `terragrunt hcl format` pass with no changes required (this unit only
  touches GitOps content, not Terraform, so these are a no-op sanity check).
- ArgoCD Application `platform-sealed-secrets` reaches `Synced`/`Healthy`.

---

- [ ] U2. **Retrofit `platform/arc-systems` with explicit resources**

**Goal:** Set explicit CPU/memory requests+limit on the GitHub Actions Runner Controller's
controller Deployment.

**Requirements:** R1, R2, R3, R11

**Dependencies:** None

**Files:**
- Modify: `platform/arc-systems/values.yaml`

**Approach:**
- Set resources at `gha-runner-scale-set-controller.resources.requests`/`.limits` — **verified
  directly** via `helm show values oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller --version 0.13.1`
  during planning: `resources` is a single top-level key (one container, no nesting), currently
  `{}` with the chart's own comment recommending against a default so environments like Minikube
  aren't forced into a floor — this repo's constrained cluster is exactly the case that comment
  anticipates, and explicit values are still the right call here per R1-R3.
- Same CPU-request-only / memory-request+limit shape and inline-comment convention as U1.

**Patterns to follow:**
- U1's approach; `platform/arc-systems/values.yaml`'s current minimal structure.

**Test scenarios:**
- Happy path: `helm template` renders the controller-manager Deployment with the declared
  requests/limits, no CPU limit present.
- Integration: after sync, the running controller pod's resources match; the controller continues
  reconciling `arc-runners`' `AutoscalingRunnerSet` without new errors in its logs.

**Verification:**
- ArgoCD Application `platform-arc-systems` reaches `Synced`/`Healthy`; `arc-runners` continues
  scaling runners normally after the change (no regression in the existing
  `controllerServiceAccount` cross-namespace RBAC wiring).

---

- [ ] U3. **Retrofit `platform/arc-runners`: hand-authored `dind` spec, resources, sized `emptyDir`**

**Goal:** Replace the currently-unset `containerMode` with an explicit, hand-authored `dind` pod
spec carrying resource requests/limits on both containers and `sizeLimit` on all three `emptyDir`
volumes.

**Requirements:** R1, R2, R3, R4, R5, R12

**Dependencies:** None. (`dind` necessity was confirmed during document review — `arc-runners`'
CI jobs genuinely build/run Docker images, so this unit proceeds as scoped. The node-isolation
mitigation for the privileged `dind` container was also resolved during document review as a
separate follow-up plan/unit — see Scope Boundaries → Deferred to Follow-Up Work — so it does not
block this unit; once that follow-up lands, this unit's spec will need a matching
`nodeSelector`/toleration added.)

**Files:**
- Modify: `platform/arc-runners/values.yaml`

**Approach:**
- Do **not** set `containerMode.type: dind` (mutually exclusive with volume customization per
  upstream docs — see Key Technical Decisions). Instead, author `template.spec` directly under
  `gha-runner-scale-set.template.spec`, copying the chart's own documented dind blueprint
  (`init-dind-externals` initContainer, `dind` sidecar container, `runner` container) verbatim as
  the starting point, then adding: resource requests/limits per the Key Technical Decisions table
  to the `runner` and `dind` containers, and `sizeLimit` to the `work`, `dind-sock`, and
  `dind-externals` `emptyDir` volumes.
- Add a comment citing the exact upstream chart version this blueprint was copied from, so a future
  chart version bump prompts a manual re-diff rather than silent drift.

**Technical design:** *(directional guidance only, not implementation-ready YAML)*
```yaml
# gha-runner-scale-set.template.spec, hand-authored from the <chart-version> dind blueprint
# (containerMode.type: dind cannot be combined with emptyDir sizeLimit customization -- see
# platform/arc-runners retrofit notes). Re-diff against the upstream blueprint on chart bumps.
spec:
  initContainers:
    - name: init-dind-externals
      # ...copied from upstream, unmodified...
  containers:
    - name: dind
      resources: { requests: {cpu: 250m, memory: 256Mi}, limits: {memory: 1024Mi} }
      volumeMounts:
        - {name: work, mountPath: /home/runner/_work}
        - {name: dind-sock, mountPath: /var/run}
        - {name: dind-externals, mountPath: /home/runner/externals}
    - name: runner
      resources: { requests: {cpu: 500m, memory: 512Mi}, limits: {memory: 1536Mi} }
      volumeMounts:
        - {name: work, mountPath: /home/runner/_work}
        - {name: dind-sock, mountPath: /var/run}
  volumes:
    - name: work
      emptyDir: {sizeLimit: 5Gi}
    - name: dind-sock
      emptyDir: {sizeLimit: 16Mi}
    - name: dind-externals
      emptyDir: {sizeLimit: 1Gi}
```

**Patterns to follow:**
- Upstream `gha-runner-scale-set` `values.yaml`'s own commented-out dind reference blueprint (the
  authoritative source to copy from).

**Test scenarios:**
- Happy path: `helm template` renders a runner pod spec matching the hand-authored blueprint, with
  requests/limits and `sizeLimit` present on all three volumes.
- Happy path: a real CI job dispatched through `arc-runners` completes successfully end-to-end
  (checkout, build/test step, teardown) under the new resource bounds.
- Edge case: a CI job whose working directory exceeds `5Gi` fails predictably (disk-pressure/quota
  error) rather than silently filling node disk — confirms the `sizeLimit` is actually enforced.
- Edge case: a CI job with a larger-than-usual memory footprint is throttled/OOM-killed rather than
  starving sibling pods on the same node — confirms the memory limit provides real isolation.
- Integration: `dind`'s Docker daemon starts successfully and the `runner` container can execute
  `docker build`/`docker run` against it under the hand-authored spec (proves the manual blueprint
  copy didn't drop a required env var, mount, or probe).

**Verification:**
- ArgoCD Application `platform-arc-runners` reaches `Synced`/`Healthy`.
- At least one real GitHub Actions workflow run completes successfully post-change.

---

- [ ] U4. **Register the `vpa` destination namespace in the `platform` tier's Terraform allow-list**

**Goal:** Extend `platform_destination_namespaces` so a new `platform/vpa/` GitOps directory is
permitted to sync, before that directory is authored.

**Requirements:** R6 (prerequisite)

**Dependencies:** None

**Files:**
- Modify: `infra/modules/argocd-gitops/variables.tf`

**Approach:**
- Add `"vpa"` to the `platform_destination_namespaces` variable's `default` list.
- Add an inline comment (mirroring the existing comment style in that variable block) confirming
  the no-per-stack-override pattern is deliberate, so production's eventual `argocd-gitops` stack
  inherits `vpa` automatically without a future editor needing to re-derive this.

**Patterns to follow:**
- The existing inline comments on the `arc-runners` and `sealed-secrets` entries in the same
  variable block.

**Test scenarios:**
- Test expectation: none -- pure Terraform variable default change with no conditional logic;
  covered by the standard validation workflow below, not a behavioral test.

**Verification:**
- `terragrunt hcl format` and `terragrunt hcl validate` pass (repo-root, per `AGENTS.md`).
- `cd infra/environments/staging/argocd-gitops && terragrunt init -reconfigure && terragrunt
  validate` passes (per `AGENTS.md`'s "Staging ArgoCD GitOps" environment-specific check).
- After `terragrunt apply`, the `platform` `AppProject`'s destination list includes `vpa`
  (`kubectl get appproject platform -o yaml` or ArgoCD UI).

---

- [ ] U5. **Author `platform/vpa/` wrapper chart (Recommender-only)**

**Goal:** Install the VPA Recommender component (and its CRD/RBAC) as a new `platform`-tier chart,
with the Updater and admission-controller explicitly disabled.

**Requirements:** R1, R2, R6, R13 (referenced by)

**Dependencies:** U4 (namespace must be allow-listed before this Application can sync)

**Files:**
- Create: `platform/vpa/Chart.yaml`
- Create: `platform/vpa/values.yaml`

**Approach:**
- `Chart.yaml`: single `dependencies` entry pinning `vertical-pod-autoscaler` chart `0.11.0` from
  `https://kubernetes.github.io/autoscaler`, following the exact structure of the three existing
  wrapper `Chart.yaml` files (`apiVersion: v2`, `name: vertical-pod-autoscaler-wrapper`,
  `version: 0.1.0`).
- `values.yaml`: nest values under `vertical-pod-autoscaler:` (**verified** — no `alias:` is
  needed; the chart has no bundled `metrics-server` subchart to worry about disabling, unlike an
  earlier assumption). Set `updater.enabled: false`, `admissionController.enabled: false`,
  `recommender.replicas: 1`, `recommender.podDisruptionBudget.enabled: false`, and
  `recommender.resources.requests.cpu`/`.requests.memory`/`.limits.memory` per the Key Technical
  Decisions table (no CPU limit override, consistent with R1). All of these keys were **confirmed
  by running `helm show values` against the pinned chart version during planning** — this is the
  exact, verified values schema, not an assumption.
- **Live-rendered and verified during planning** (`helm template --include-crds` against this
  exact `Chart.yaml`/`values.yaml` pair, in a scratch directory, using this repo's real pinned
  chart version): the recommender-only configuration renders exactly 1 `Deployment`, 1
  `ServiceAccount`, 2 `CustomResourceDefinition`s, 5 `ClusterRole`s, and 5 `ClusterRoleBinding`s —
  **all five bindings are scoped to `*-recommender-*` names only** (this chart gates
  ClusterRoleBindings per-component more precisely than the Fairwinds chart researched earlier;
  there are no dangling updater/admission-controller bindings at all). Zero
  `MutatingWebhookConfiguration` or any other kind is rendered. Total rendered manifest size is
  ~62KB. This is concrete proof from a live dry-run, not an inference from chart docs.

**Patterns to follow:**
- `platform/arc-systems/Chart.yaml` / `values.yaml` — closest existing analog (single controller,
  no extra static templates needed in this unit; CRs are added separately in U6).

**Test scenarios:**
- Happy path: `helm template` renders exactly one Recommender Deployment, its CRD
  (`verticalpodautoscalers.autoscaling.k8s.io` + checkpoint CRD), and its RBAC — no Updater
  Deployment, no admission-controller Deployment, no `MutatingWebhookConfiguration` anywhere in
  the rendered output.
- Integration: after sync, `kubectl get pods -n vpa` shows exactly one Recommender pod, `Running`
  and `Ready`, with no restarts in the first several minutes.
- Edge case: confirm the rendered CRD's size and any large-annotation risk is actually covered by
  the `platform` tier's existing `ServerSideApply=true` (not a new decision, but worth a one-time
  live confirmation given the vendor's own CRD-upgrade caveat).

**Verification:**
- ArgoCD Application `platform-vpa` reaches `Synced`/`Healthy`.
- `kubectl get crd verticalpodautoscalers.autoscaling.k8s.io` exists; no `updater`/
  `admission-controller` Deployments or ServiceAccounts exist in the `vpa` namespace.

---

- [ ] U6. **Add per-workload `VerticalPodAutoscaler` CR objects (`sealed-secrets` and `arc-systems` only)**

**Goal:** Create one recommendation-only `VerticalPodAutoscaler` object per workload that VPA can
actually target, so usage data begins accumulating.

**Requirements:** R6, R7

**Scope correction (found during document review, confirmed by live `helm template` verification):**
`arc-runners` is **excluded** from this unit. VPA's `targetRef` mechanism only resolves pods for
well-known controller kinds (Deployment/ReplicaSet/StatefulSet/etc.) or a CR that implements the
`/scale` subresource. `arc-runners`' actual runner workload is the `gha-runner-scale-set` chart's
`AutoscalingRunnerSet` object (verified by rendering the pinned chart version: it creates exactly
one `AutoscalingRunnerSet`, plus `Role`/`RoleBinding`/`ServiceAccount` — **no Deployment,
ReplicaSet, or StatefulSet at all**). The controller reconciles that object into
`EphemeralRunnerSet` → `EphemeralRunner` → Pod at runtime, entirely outside what this chart
renders, and neither CRD defines a `/scale` subresource. A VPA object targeting it would sit with
an empty `.status.recommendation` indefinitely with no error surfaced — silently failing R7 for
exactly the workload (privileged, resource-variable CI jobs) this effort most wants insight into.
`arc-runners`' resource values (set directly in U3) are therefore the only right-sizing signal for
that chart until/unless a future VPA release adds ARC-compatible target resolution; revisit
manually using real job history in the interim (see U7's convention doc).

**Dependencies:** U1, U2 (target charts must exist with their final Deployment names), U5
(CRD must be live for the CR to validate against the API server — sequencing note, not a hard
authoring blocker since ArgoCD's `self_heal` will retry a transient admission failure)

**Files:**
- Create: `platform/sealed-secrets/templates/vpa.yaml`
- Create: `platform/arc-systems/templates/vpa.yaml`

**Approach:**
- Each manifest is a static `VerticalPodAutoscaler` object (not chart-templated), following the
  `platform/arc-runners/templates/sealed-secret.yaml` precedent for static content inside a wrapper
  chart's `templates/` directory.
- `spec.targetRef` points to each chart's own Deployment (confirm exact rendered Deployment name
  per chart during implementation, since Helm's naming template may prefix/suffix it).
- `spec.updatePolicy.updateMode: "Off"` on both — the zero-mutation, recommendation-only mode.
- `spec.resourcePolicy.containerPolicies` uses `containerName: '*'` with sensible
  `minAllowed`/`controlledResources: ["cpu", "memory"]` bounds, **and `controlledValues:
  RequestsOnly`** (found during document review: VPA's `controlledValues` field defaults to
  `RequestsAndLimits`, which would surface CPU-limit recommendations that directly contradict this
  plan's own CPU-request-only policy — `RequestsOnly` keeps recommendations consistent with R1).
- No explicit `metadata.namespace` is set — each CR inherits its own Application's already
  whitelisted destination namespace at apply time (see Key Technical Decisions).

**Test scenarios:**
- Happy path: after each Application syncs, `kubectl get vpa -A` shows two `VerticalPodAutoscaler`
  objects (`sealed-secrets`, `arc-systems` namespaces), each with `updateMode: Off` and
  `controlledValues: RequestsOnly`.
- Integration: after a warm-up period, `kubectl describe vpa <name> -n <namespace>` shows a
  populated `.status.recommendation` for each of the two targets, with no CPU-limit value present
  in the recommendation and no corresponding pod restart or eviction event attributable to VPA.
- Edge case: if a CR is applied before the CRD exists (a transient sync-ordering race across
  independent Applications), ArgoCD's `self_heal` retries the CR on the next reconcile loop rather
  than failing permanently -- confirm this recovers without manual intervention on first rollout.

**Verification:**
- Both `VerticalPodAutoscaler` objects reach a steady state with no `Error`/`Degraded` status
  on their owning Application.
- `.status.recommendation` is populated for both within a reasonable observation window
  (hours to low-single-digit days, depending on workload activity).
- `arc-runners` has no `VerticalPodAutoscaler` object anywhere in the repo — confirms the scope
  exclusion above was actually honored, not accidentally reintroduced.

---

- [ ] U7. **Write the resource-management convention doc**

**Goal:** Capture the CPU/memory/`emptyDir` policy, VPA recommender-only usage, KEDA/HPA/VPA
decision criteria, and operational notes so a future contributor can follow this policy without
re-deriving it.

**Requirements:** R9, R13

**Dependencies:** None (can be authored in parallel with U1-U6, though it should reference their
final shape before being considered complete)

**Files:**
- Create: `docs/resource-management-policy.md`

**Approach:**
- Mirror `docs/gitops-repo-scaffold.md`'s reference-doc structure: flat file under `docs/`, YAML
  frontmatter (`date:`, `topic:`), opening paragraph naming this plan and its origin brainstorm as
  provenance.
- Cover, at minimum: the CPU-request-only/memory-request+limit rule (R1-R3); the `emptyDir`
  `sizeLimit` rule (R4); the recommender-only VPA usage pattern and how to add a new
  `VerticalPodAutoscaler` CR for a future workload, **including the caveat that VPA only works for
  workloads with a Deployment/ReplicaSet/StatefulSet or `/scale`-subresource lineage** —
  ephemeral, controller-managed pods like ARC's runner pods need manual/observational tuning
  instead (R6, R7 pattern, `arc-runners` exclusion); the four-way autoscaling decision
  criteria — no autoscaling / HPA / KEDA / VPA-only (R9); an interim operator runbook for
  triaging a CI job that gets OOM-killed under the shared memory limit (checking
  `kubectl describe pod` for `OOMKilled`, since no alerting exists yet); the vendor-documented
  VPA CRD-upgrade-is-manual caveat and what to do about it on a future chart version bump; and a
  rollback note that a bad resource value should be fixed by reverting the Git commit, not by
  `kubectl edit`, since the `platform` `ApplicationSet`'s `self_heal` will silently overwrite manual
  edits.

**Test scenarios:**
- Test expectation: none -- documentation content, not executable behavior.

**Verification:**
- The doc exists, follows the established frontmatter/structure convention, and covers every topic
  listed above without needing a follow-up edit to fill an obvious gap.

---

- [ ] U8. **Reference the convention doc from `apps/README.md` and `platform/README.md`**

**Goal:** Make the new convention doc discoverable the same way `docs/gitops-repo-scaffold.md` and
the migration-requirements brainstorm already are.

**Requirements:** R14

**Dependencies:** U7

**Files:**
- Modify: `apps/README.md`
- Modify: `platform/README.md`

**Approach:**
- Add one sentence to each README's existing closing reference paragraph, in the same spot the
  `docs/gitops-repo-scaffold.md` and migration-requirements-brainstorm sentences already sit,
  pointing to `docs/resource-management-policy.md`.

**Test scenarios:**
- Test expectation: none -- documentation link addition, not executable behavior.

**Verification:**
- Both READMEs render correctly (valid Markdown, working relative links) and mention the new doc.

---

## System-Wide Impact

- **Interaction graph:** ArgoCD's `platform` `ApplicationSet` reconciles all four affected
  Applications (`platform-sealed-secrets`, `platform-arc-systems`, `platform-arc-runners`,
  `platform-vpa`) independently and on its own poll interval — there is no cross-Application sync
  ordering/wave configured, so the VPA CRD and the two CR objects (`sealed-secrets`, `arc-systems`
  — `arc-runners` is excluded, see U6) may sync in any relative order on first rollout (mitigated
  by `self_heal` retry, per U6).
- **Error propagation:** A bad resource value causing `CrashLoopBackOff` will be silently
  re-applied on every `self_heal` reconcile loop rather than paused — the only correct recovery
  path is reverting the offending Git commit (documented in U7's convention doc), not editing the
  live object.
- **State lifecycle risks:** First-rollout race between the VPA CRD (via `platform-vpa`) and the
  two CR objects (via their own Applications) is a transient-consistency risk, not a permanent
  one, given `self_heal`. A future VPA chart version bump carries the vendor-documented
  CRD-non-upgrade risk (Deferred to Follow-Up Work).
- **API surface parity:** N/A — no external API surface in this GitOps content; the only "API" is
  the Kubernetes resource specs themselves, which this plan changes directly.
- **Integration coverage:** Live ArgoCD sync verification (per-unit `Verification` sections) is the
  only way most of these risks surface — none of the RBAC/CRD-size/namespace-allow-list/PSA
  interactions are observable via `terraform validate`/`terragrunt hcl validate` alone, consistent
  with this repo's own established pattern (see the migration plan's empirical-verification units).
- **Unchanged invariants:** The `apps`/`platform` RBAC trust boundary itself is not modified by
  this plan — `platform_cluster_resource_whitelist` is **confirmed** (via a live `helm template
  --include-crds` dry-run during planning, see U5) to already cover everything VPA's
  recommender-only configuration renders, with no extension needed; the same inline comment in
  `infra/modules/argocd-gitops/main.tf` remains the correct, minimal-diff extension point should
  any future platform-tier app need a kind beyond today's whitelist. **Found during document
  review:** the recommender's `target-reader`-class `ClusterRole` grants cluster-wide `get`/`list`/
  `watch` on core workload kinds (Pods, Nodes, Deployments, ReplicaSets, StatefulSets, Jobs,
  CronJobs) and a wildcard `*/scale` subresource across every namespace, including any future
  `apps`-tier namespace — a normal, low-sensitivity VPA requirement (no Secrets access) but worth
  stating explicitly given this repo's otherwise careful two-tier trust-boundary framing.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Official VPA chart is vendor-flagged "not ready for production use" | Recommender-only mode + `updateMode: Off` on every CR bounds the blast radius to zero pod mutation regardless of chart maturity (user-accepted during planning) |
| Hand-authored `dind` pod spec drifts from the upstream chart's reference blueprint on future version bumps | Comment records the exact chart version the blueprint was copied from; re-diff manually on bumps |
| VPA CRD may not auto-upgrade via Helm's own documented limitation | Verify ArgoCD's `helm template --include-crds` re-render behavior live at first sync and at the next chart bump; fall back to a manual `kubectl apply --server-side` step if it doesn't hold |
| A `self_heal`-driven reconcile silently reapplies a bad resource value, causing repeated `CrashLoopBackOff` | Convention doc documents Git-revert as the only correct rollback path |
| CI jobs have genuinely unpredictable memory profiles and may exceed the shared conservative limit | Interim manual OOM-triage runbook documented in U7, pending Prometheus/Grafana; VPA data will inform future headroom tuning |
| First-rollout sync-ordering race between VPA's CRD and the two CR objects | `self_heal` retries automatically; treated as a transient, self-resolving condition, not a blocker |
| `arc-runners`' ephemeral runner pods have no VPA-resolvable target (found during document review), so R7 has no automated right-sizing signal for that chart at all | U3's manually-set values are the only sizing mechanism for `arc-runners`; revisit periodically using real job history (documented in U7) until/unless VPA gains ARC-compatible target support |
| `dind`'s `privileged: true` container shares a Docker socket (`dind-sock`) with the `runner` container that executes arbitrary, potentially third-party CI job code — found during document review (security-lens); a compromised job can reach node-level access via that socket, and `platform`-tier namespaces carry no Pod Security Standard enforcement to contain it | **Resolved:** dedicate `arc-runners` to a tainted node pool to bound blast radius, tracked as a separate follow-up plan/unit (see Scope Boundaries → Deferred to Follow-Up Work) since it touches node provisioning, not GitOps chart content. Until that lands, the exposure is a known, accepted interim condition. |
| `arc-runners`' CI jobs were confirmed (user-confirmed during document review) to genuinely require Docker-in-Docker — jobs build/run Docker images — so `dind` mode and its hand-authored spec are the correct approach, not an unverified assumption | Closed; no further action needed. This closes the origin brainstorm's flagged-but-never-verified research item. |

| Production will eventually inherit these values untested against its own fixed-capacity pool | Tracked explicitly as a Deferred-to-Follow-Up item — review before production's `argocd-gitops` stack is created |

---

## Documentation / Operational Notes

- `docs/resource-management-policy.md` (U7) is the durable artifact future contributors consult;
  `apps/README.md`/`platform/README.md` (U8) make it discoverable.
- No monitoring/alerting exists yet for OOM kills or VPA recommendation drift — the interim runbook
  in U7 is a manual `kubectl` triage step until Prometheus/Grafana lands.
- Recommend capturing a `/ce-compound` learning after this lands, specifically on: VPA chart
  selection tradeoffs, the `containerMode`/`emptyDir` mutual-exclusivity finding, and whatever the
  live CRD-upgrade-on-sync behavior turns out to be — per the learnings researcher's note that no
  existing `docs/solutions/` doc covers any of these yet.

---

## Sources & References

- **Origin document:** [docs/brainstorms/helm-chart-resource-management-requirements.md](../brainstorms/helm-chart-resource-management-requirements.md)
- Related code: `infra/modules/argocd-gitops/variables.tf`, `infra/modules/argocd-gitops/main.tf`,
  `platform/arc-runners/values.yaml`, `platform/arc-runners/templates/sealed-secret.yaml`
- Related docs: `docs/gitops-repo-scaffold.md`,
  `docs/solutions/architecture-patterns/argocd-two-tier-rbac-boundary-and-arc-onboarding-2026-08-02.md`,
  `docs/solutions/architecture-patterns/self-hosted-gitops-monorepo-migration-terragrunt-sops-state-preservation-2026-08-01.md`
- External docs: `https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler`,
  `https://kubernetes.github.io/autoscaler` (Helm repo), `https://github.com/bitnami/charts/blob/main/bitnami/common/templates/_resources.tpl`
  (external sizing-heuristic reference only — not the pinned `sealed-secrets` chart's own default,
  see Context & Research), `https://github.com/bitnami/sealed-secrets` (pinned chart `2.19.1`,
  live-verified via `helm show values` during document review)
