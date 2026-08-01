# apps/

Low-trust tier: ordinary apps with no cluster-scoped resource creation rights **and no namespaced
Role/RoleBinding creation rights either** (that boundary is load-bearing, not a defense-in-depth
nicety -- this is the tier ordinary cluster users, not cluster admins, will eventually push to, and
an RBAC-escalation path is never an acceptable risk here). Synced by ArgoCD's `apps`
`ApplicationSet` (git directory generator watching `apps/*` by default — configurable via
`var.gitops_apps_path`, see `infra/modules/argocd-gitops/main.tf`). Each subdirectory here becomes
an ArgoCD `Application` in the `apps` `AppProject`, and the directory's basename is the sync
destination namespace.

This directory currently holds only this placeholder — no ordinary (non-RBAC-creating) app has
been added yet. `gha-runner-scale-set` was tried here first but found (during live testing, see
`docs/plans/2026-07-30-001-feat-argocd-gitops-migration-plan.md` U7) to need its own namespace-
scoped `Role`/`RoleBinding`, so it now lives under `platform/arc-runners/` instead. Any future
ordinary app follows the same pattern: a thin wrapper `Chart.yaml` (or Kustomize
`kustomization.yaml`), a `values.yaml`, and any `SealedSecret` manifests it needs -- provided it
truly needs no RBAC-object or cluster-scoped creation rights.

See [docs/gitops-repo-scaffold.md](../docs/gitops-repo-scaffold.md) for the exact expected layout
and ready-to-copy content, and
[docs/brainstorms/argocd-gitops-migration-requirements.md](../docs/brainstorms/argocd-gitops-migration-requirements.md)
for the architectural decisions behind the two-tier `apps`/`platform` split. See
[docs/resource-management-policy.md](../docs/resource-management-policy.md) for the CPU/memory/
`emptyDir` sizing policy and autoscaling decision criteria every chart here should follow.
