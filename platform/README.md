# platform/

Privileged tier: apps that genuinely need cluster-scoped install rights (e.g. controllers that
install their own CRDs), synced by ArgoCD's `platform` `ApplicationSet` (git directory generator
watching `platform/*`, see `infra/modules/argocd-gitops/main.tf`). Each subdirectory here becomes an
ArgoCD `Application` in the `platform` `AppProject`, whitelisted for only the specific
cluster-scoped kinds named in `var.platform_cluster_resource_whitelist`.

This directory currently holds only this placeholder — real per-app content is a follow-up
increment once a live cluster is available. `platform`-tier secrets use SOPS+KSOPS with a
dedicated AGE key pair (the mount mechanism into `argocd-repo-server` is already live; the key
value itself is still a placeholder pending generation); the `.sops.yaml` rule for
`platform/**/*.sops.yaml` is added once real platform-tier content exists to match against.

See [docs/gitops-repo-scaffold.md](../docs/gitops-repo-scaffold.md) for the exact expected layout
and ready-to-copy content, and
[docs/brainstorms/argocd-gitops-migration-requirements.md](../docs/brainstorms/argocd-gitops-migration-requirements.md)
for the architectural decisions behind the two-tier `apps`/`platform` split.
