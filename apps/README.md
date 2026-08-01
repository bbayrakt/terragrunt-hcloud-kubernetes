# apps/

Low-trust tier: ordinary apps with no cluster-scoped resource creation rights, synced by ArgoCD's
`apps` `ApplicationSet` (git directory generator watching `apps/*`, see
`modules/argocd-gitops/main.tf`). Each subdirectory here becomes an ArgoCD `Application` in the
`apps` `AppProject`, and the directory's basename is the sync destination namespace.

This directory currently holds only this placeholder — real per-app content (Helm-chart-based or
Kustomize-based, plus any `SealedSecret` manifests) is a follow-up increment once the Sealed
Secrets controller and a live cluster are available.

See [docs/gitops-repo-scaffold.md](../docs/gitops-repo-scaffold.md) for the exact expected layout
and ready-to-copy content, and
[docs/brainstorms/argocd-gitops-migration-requirements.md](../docs/brainstorms/argocd-gitops-migration-requirements.md)
for the architectural decisions behind the two-tier `apps`/`platform` split.
