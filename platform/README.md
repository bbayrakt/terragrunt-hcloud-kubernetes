# platform/

Privileged tier: apps that genuinely need cluster-scoped install rights (e.g. controllers that
install their own CRDs), synced by ArgoCD's `platform` `ApplicationSet` (git directory generator
watching `platform/*`, see `infra/modules/argocd-gitops/main.tf`). Each subdirectory here becomes an
ArgoCD `Application` in the `platform` `AppProject`, whitelisted for only the specific
cluster-scoped kinds named in `var.platform_cluster_resource_whitelist`.

This directory hosts real per-app content: `arc-systems/` (the GitHub Actions runner scale set's
controller, which installs its own CRDs), `arc-runners/` (the runner scale set instance itself --
moved here from `apps/` during live testing, since it needs to create its own namespace-scoped
`Role`/`RoleBinding` granting the `arc-systems` controller's ServiceAccount cross-namespace access,
an RBAC-creating operation the `apps` tier must never permit), and `sealed-secrets/` (the Sealed
Secrets controller itself, the first `platform`-tier app bootstrapped — see `docs/plans/2026-07-30-
001-feat-argocd-gitops-migration-plan.md` U5/U6/U7). `platform`-tier secrets use SOPS+KSOPS with a
dedicated AGE key pair (the mount mechanism into `argocd-repo-server` is live; the key value itself
is still a placeholder pending generation, since none of the current platform-tier apps need a
SOPS-encrypted secret yet -- `arc-runners`' `github-arc-pat` uses a `SealedSecret` instead); the
`.sops.yaml` rule for `platform/**/*.sops.yaml` is added once a real platform-tier app needs one.

See [docs/gitops-repo-scaffold.md](../docs/gitops-repo-scaffold.md) for the exact expected layout
and ready-to-copy content, and
[docs/brainstorms/argocd-gitops-migration-requirements.md](../docs/brainstorms/argocd-gitops-migration-requirements.md)
for the architectural decisions behind the two-tier `apps`/`platform` split. See
[docs/resource-management-policy.md](../docs/resource-management-policy.md) for the CPU/memory/
`emptyDir` sizing policy and autoscaling decision criteria every chart here should follow.
