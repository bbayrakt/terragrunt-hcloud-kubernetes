# apps/

Low-trust tier: ordinary apps with no cluster-scoped resource creation rights, synced by ArgoCD's
`apps` `ApplicationSet` (git directory generator watching `apps/*` by default — configurable via
`var.gitops_apps_path`, see `infra/modules/argocd-gitops/main.tf`). Each subdirectory here becomes
an ArgoCD `Application` in the `apps` `AppProject`, and the directory's basename is the sync
destination namespace.

This directory hosts real per-app content: `arc-runners/` (the GitHub Actions runner scale set,
migrated off Terraform-managed Helm — see `docs/plans/2026-07-30-001-feat-argocd-gitops-migration-
plan.md` U7). Each new ordinary app follows the same pattern: a thin wrapper `Chart.yaml` (or
Kustomize `kustomization.yaml`), a `values.yaml`, and any `SealedSecret` manifests it needs.

See [docs/gitops-repo-scaffold.md](../docs/gitops-repo-scaffold.md) for the exact expected layout
and ready-to-copy content, and
[docs/brainstorms/argocd-gitops-migration-requirements.md](../docs/brainstorms/argocd-gitops-migration-requirements.md)
for the architectural decisions behind the two-tier `apps`/`platform` split.
