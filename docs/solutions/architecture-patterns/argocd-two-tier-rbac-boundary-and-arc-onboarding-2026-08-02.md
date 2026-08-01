---
title: ArgoCD Two-Tier apps/platform Trust Boundary — the RBAC Rule and Live Onboarding Gotchas
date: 2026-08-02
last_updated: 2026-08-01
category: architecture-patterns
module: argocd-gitops
problem_type: architecture_pattern
component: tooling
severity: high
applies_when:
  - "Onboarding any new Helm chart or Kustomize app into this repo's apps/ or platform/ GitOps tiers"
  - "A chart creates its own namespace-scoped Role/RoleBinding as part of normal operation (common in cross-namespace controller/agent patterns)"
  - "A chart's CRDs are large (multiple custom types with extensive OpenAPI schemas)"
  - "A chart auto-discovers a sibling component (e.g. a controller's ServiceAccount) via a Helm lookup() based on labels"
  - "Deciding whether a new app belongs in the apps tier or the platform tier"
  - "Authoring a static manifest (VerticalPodAutoscaler, PodDisruptionBudget, NetworkPolicy, or similar) that references another ArgoCD/Helm-rendered resource's name via targetRef/selector/similar"
tags: [argocd, appproject, rbac, trust-boundary, gitops, helm, crd, actions-runner-controller, vpa, release-naming]
related_components: [argocd-gitops-stack]
---

# ArgoCD Two-Tier apps/platform Trust Boundary — the RBAC Rule and Live Onboarding Gotchas

## Context

This repo's GitOps content (`apps/`, `platform/`) is split into two ArgoCD `AppProject` trust
tiers by design (see `docs/brainstorms/argocd-gitops-migration-requirements.md`):

- **`apps`** — the tier ordinary cluster *users* (not cluster admins) will eventually push to.
  No cluster-scoped resource rights, no namespace-scoped RBAC-object (`Role`/`RoleBinding`)
  creation rights either.
- **`platform`** — cluster-admin-authored only. Explicit whitelist of cluster-scoped kinds
  (CRDs, `ClusterRole`, `ClusterRoleBinding`) that known platform-tier apps need.

Onboarding the GitHub Actions Runner Controller (ARC) — a controller chart plus a runner
scale-set chart — through this model surfaced one architecture-defining rule and three
independent live-testing gotchas, none of which were caught by `terraform plan`/`validate` since
they only manifest once ArgoCD actually renders and syncs the chart against a live cluster.

## Guidance

### The rule: RBAC-object creation rights are a tier-assignment decision, not a risk tradeoff

If a chart unconditionally creates its own `Role`/`RoleBinding` (even a fully self-contained one
that only binds its own namespace-scoped `Role` — not a reference to some pre-existing, possibly
dangerous `ClusterRole`), **that chart belongs in `platform/`, never `apps/`** — even under a
"solo-operator, no other trust boundary matters yet" framing.

Why the framing matters: `apps` tier is not "code nobody else touches yet." It's an
inception-level design commitment that ordinary, less-trusted cluster users will eventually push
there. Loosening the `apps` `AppProject`'s `namespace_resource_blacklist` for `Role`/`RoleBinding`
to unblock one chart reopens a real, well-known Kubernetes escalation path for *every* future
`apps`-tier manifest: a `RoleBinding` can reference a pre-existing `ClusterRole` (including
`cluster-admin`, which always exists), and if that `ClusterRole`'s rules include cluster-scoped
resource types, those rules apply cluster-wide even through a namespace-scoped binding. ArgoCD's
`namespace_resource_blacklist` is kind-level only — it cannot distinguish "this app's own
self-contained Role" from "this app is borrowing a dangerous pre-existing ClusterRole." There is
no narrower ArgoCD-native middle ground; the correct fix is always to re-home the chart to
`platform/`, not to carve an exception into the `apps` boundary.

```hcl
# infra/modules/argocd-gitops/main.tf -- apps AppProject (correct, permanent state)
resource "argocd_project" "apps" {
  spec {
    cluster_resource_whitelist {
      group = ""
      kind  = "Namespace"           # needed for CreateNamespace=true; see gotcha #1 below
    }

    namespace_resource_blacklist {   # NEVER remove this to unblock a chart -- move the chart
      group = "rbac.authorization.k8s.io"
      kind  = "Role"
    }
    namespace_resource_blacklist {
      group = "rbac.authorization.k8s.io"
      kind  = "RoleBinding"
    }
  }
}
```

### Gotcha 1 — `CreateNamespace=true` needs an explicit `Namespace` whitelist entry

`CreateNamespace=true`'s PreSync namespace-creation step is itself a cluster-scoped resource
operation and is subject to the `AppProject`'s cluster-resource rules like any other kind.
Omitting `{group: "", kind: "Namespace"}` from `platform_cluster_resource_whitelist` makes
*every* platform-tier app's first sync fail outright:

```
resource :Namespace is not permitted in project platform
```

Fix: add the entry to the whitelist. This is safe even for the low-trust `apps` tier: an
`Application`'s `destination.namespace` is already validated against that tier's namespace
allow-list at the `AppProject` level, so whitelisting `Namespace` can only ever create one of the
pre-approved namespaces, never an arbitrary one.

A related trap: if an `AppProject` also carries a blanket `cluster_resource_blacklist{group="*",
kind="*"}` (as this repo's `apps` project originally did, for "defense in depth"), adding
`Namespace` to the whitelist does **not** unblock it — ArgoCD requires a resource to be
whitelist-included *and* not blacklist-excluded, so a matching wildcard blacklist entry silently
re-excludes anything the whitelist just allowed. A blanket blacklist and a narrow whitelist
exception are mutually exclusive, not layered defense-in-depth. Remove the wildcard blacklist
once you have an intentional whitelist — trying to keep both produces a confusing "I whitelisted
it but it's still blocked" failure.

### Gotcha 2 — large chart CRDs need `ServerSideApply=true`

`gha-runner-scale-set-controller`'s CRDs (`autoscalinglisteners`, `autoscalingrunnersets`,
`ephemeralrunners`, `ephemeralrunnersets`, all under `actions.github.com`) are large enough that
client-side apply's `kubectl.kubernetes.io/last-applied-configuration` annotation exceeds
Kubernetes' 262144-byte annotation limit:

```
CustomResourceDefinition.apiextensions.k8s.io "autoscalinglisteners.actions.github.com" is
invalid: metadata.annotations: Too long: may not be more than 262144 bytes
```

This is a known upstream `actions-runner-controller` issue, not specific to this repo. Server-side
apply never writes that annotation, so it isn't subject to the limit:

```hcl
sync_options = [
  "CreateNamespace=true",
  "ServerSideApply=true",
]
```

Scope this to whichever tier's `ApplicationSet` actually installs CRD-bearing charts (`platform`
in this repo) rather than applying it blanket — it's a targeted fix for a specific chart's CRD
size, not a tier-wide requirement.

After adding `ServerSideApply=true`, a stuck `Application` retrying the *old* client-side-apply
operation won't automatically pick up the new sync option — its in-progress `Operation` was
snapshotted with the old options. Delete the `Application` object outright (safe with
`preserveResourcesOnDeletion: true` — nothing already-live gets deleted) so the `ApplicationSet`
regenerates it fresh with the corrected sync options.

### Gotcha 3 — cross-namespace controller auto-discovery breaks when controller and workload are split

`gha-runner-scale-set` templates a `RoleBinding` that grants the *controller's* ServiceAccount
access to manage runner Pods in the scale-set's own namespace. To find that ServiceAccount, the
chart's `manager_role_binding.yaml` template does a Helm `lookup()` for a `Deployment` labeled
`app.kubernetes.io/part-of=gha-rs-controller` — but that lookup only searches the *release's own
namespace*. When the controller and runner scale-set intentionally live in different namespaces
(this repo's `arc-systems` / `arc-runners` split, matching the `platform`/`apps` tier boundary),
the lookup finds nothing:

```
Error: execution error at (.../templates/manager_role_binding.yaml:42:11): No gha-rs-controller
deployment found using label (app.kubernetes.io/part-of=gha-rs-controller). Consider setting
controllerServiceAccount.name in values.yaml to be explicit if you think the discovery is wrong.
```

The chart's own error message names the fix — set both explicitly rather than relying on
same-namespace auto-discovery:

```yaml
gha-runner-scale-set:
  controllerServiceAccount:
    name: platform-arc-systems-gha-rs-controller   # <release-name>-gha-rs-controller
    namespace: arc-systems
```

### Gotcha 4 — static manifests referencing a Helm-rendered resource's name must use the ApplicationSet's release-name prefix, not the bare directory basename

Any static, non-chart-templated manifest placed in a wrapper chart's `templates/` directory (this
repo's established pattern for content like `platform/arc-runners/templates/sealed-secret.yaml`)
that needs to reference another Helm-rendered resource's name — for example a
`VerticalPodAutoscaler`'s `spec.targetRef.name` pointing at that same release's Deployment — must
not assume the Deployment name equals the bare GitOps directory basename. ArgoCD's Helm release
name defaults to the `Application`'s `metadata.name`, and this repo's `ApplicationSet` template
sets that to a *prefixed* name, not the bare basename:

```hcl
# infra/modules/argocd-gitops/main.tf -- both tier ApplicationSets use this pattern
template {
  metadata {
    name = "platform-{{path.basename}}"   # "apps-{{path.basename}}" for the apps tier
  }
  ...
}
```

For `platform/arc-systems/`, this makes the actual Helm release name `platform-arc-systems`, so
the `gha-runner-scale-set-controller` chart's own naming template renders its Deployment as
`platform-arc-systems-gha-rs-controller` — **not** `arc-systems-gha-rs-controller`. A static
manifest hardcoding the bare-basename form applies cleanly (VPA objects don't validate `targetRef`
existence at admission time) but silently never resolves: `.status.recommendation` stays empty
forever with no error surfaced anywhere. This is the same naming family as Gotcha 3 above (an
ArgoCD/Helm naming assumption that looks obvious but isn't), though the mechanism differs — Gotcha
3 is a same-namespace `lookup()` scope failure; this is a hardcoded literal name in a static
manifest not accounting for the ApplicationSet's own prefixing convention.

Fix: before hardcoding any cross-reference to a Helm-rendered resource's name in a static
manifest, verify the actual rendered name — e.g. `helm template <prefixed-release-name> <chart>
--version <pinned-version> | grep -A2 '^kind: Deployment'` — rather than assuming it matches the
GitOps directory basename. Charts that set an explicit `fullnameOverride` (like this repo's
`platform/sealed-secrets/`) are an exception: `fullnameOverride` ignores the release name
entirely, so the bare, unprefixed name is correct there — check per chart, don't assume one rule
fits every chart uniformly.

## Why This Matters



None of these three gotchas are caught by `terraform hcl validate`/`terragrunt validate` — they
only surface once ArgoCD actually renders (`helm template`) and syncs the chart against a live
cluster, because they depend on real cluster state (existing namespaces, CRD size limits against
the real API server, live `Deployment` lookups). Plan documents that anticipate "author the
GitOps content, then sync/verify against the real cluster" as a distinct, separately-verified step
(rather than assuming authoring == done) are correctly modeling this risk.

The RBAC rule matters more than any single gotcha: an AppProject boundary is a security control,
not a convenience default. The instinct to "loosen the boundary a little to unblock this one
legitimate-looking case" is exactly how tiered trust models erode over time — the fix belongs in
*where the workload runs*, not in *weakening the boundary it runs under*.

## When to Apply

- Before onboarding any new chart into `apps/` or `platform/`: check whether it creates its own
  `Role`/`RoleBinding`, `ClusterRole`/`ClusterRoleBinding`, or other RBAC objects as part of normal
  operation (not just whether it needs CRDs). If it does, it belongs in `platform/`.
- Before onboarding any CRD-installing chart: check the CRDs' rendered YAML size; if any single
  CRD's manifest is large (many types, extensive schemas), add `ServerSideApply=true` to that
  tier's `ApplicationSet` sync options preemptively rather than discovering the 262144-byte limit
  live.
- Before onboarding any chart whose components are deliberately split across namespaces
  (controller vs. workload, following this repo's tier boundary): check whether the workload
  chart auto-discovers the controller via same-namespace label lookup, and set the equivalent
  "explicit reference" value if one exists.
- Whenever `CreateNamespace=true` is used in an `ApplicationSet`/`Application` sync policy: confirm
  `Namespace` is whitelisted for that tier, and confirm no blanket cluster-resource blacklist
  exists that would re-exclude it.
- Before authoring any static manifest that references another Helm-rendered resource's name
  (a `VerticalPodAutoscaler`'s `targetRef`, a `PodDisruptionBudget`'s `selector`, or similar):
  verify the actual rendered name via `helm template`, accounting for the ApplicationSet's
  `platform-`/`apps-` release-name prefix, rather than assuming it equals the bare directory
  basename.

## Examples

Full before/after Terraform diffs and the live verification sequence (namespace-forces-replace
provider quirk workaround via live `kubectl patch` + `terraform plan` zero-diff confirmation, the
`git mv apps/arc-runners platform/arc-runners` re-home, and cleanup of orphaned resources left by
the tier move — including using the `AutoscalingRunnerSet`'s own finalizer to trigger proper
GitHub-side scale-set deregistration on delete) are in the commit history around
`infra/modules/argocd-gitops/main.tf` and `infra/modules/argocd-gitops/variables.tf`, and in
`docs/plans/2026-07-30-001-feat-argocd-gitops-migration-plan.md`'s U5/U6/U7 completion notes.

## Related

- `docs/brainstorms/argocd-gitops-migration-requirements.md` — origin two-tier trust model design
  and the corrected Key Decisions entry for this exact RBAC boundary question
- `docs/plans/2026-07-30-001-feat-argocd-gitops-migration-plan.md` — U5 (Sealed Secrets bootstrap),
  U6 (ARC controller), U7 (ARC runner scale-set) completion notes with full live-testing detail
- `docs/gitops-repo-scaffold.md` — canonical `platform/arc-systems/`, `platform/arc-runners/`,
  `platform/sealed-secrets/` file contents
- `docs/solutions/integration-issues/argocd-provider-config-path-tls-cert-verification-failure-2026-07-31.md` — another ArgoCD-provider gotcha from the same migration effort (unrelated root cause, same module)
- `docs/solutions/integration-issues/dind-sidecar-restartpolicy-non-init-container-pod-validation-failure-2026-08-01.md` — a Pod-spec-level bug found in the same PR that added Gotcha 4 above (different mechanism: Kubernetes native sidecar container placement, not ArgoCD/Helm naming)
