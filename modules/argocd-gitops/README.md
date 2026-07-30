# ArgoCD GitOps Module

Configures ArgoCD (already installed by the `helm-charts` stack) via the `argoproj-labs/argocd`
Terraform provider to deploy everything else in the cluster through two trust-tiered
`AppProject`/`ApplicationSet` pairs, discovering apps automatically from a dedicated GitOps
repository instead of requiring a Terraform change per app.

See `docs/plans/2026-07-30-001-feat-argocd-gitops-migration-plan.md` for the full design
rationale (origin: `docs/brainstorms/argocd-gitops-migration-requirements.md`).

## Behavior

- **`apps` project** (default, least-privileged): blocks all cluster-scoped resource creation
  (`cluster_resource_blacklist`, though the real enforcement is the *absence* of a
  `cluster_resource_whitelist` entry), blocks namespaced `Role`/`RoleBinding` (closes a
  privilege-escalation path cluster-scoped blacklisting alone can't reach), restricts
  destinations to `var.apps_destination_namespaces`, and applies Pod Security Standard
  enforcement to any namespace it creates.
- **`platform` project** (privileged, narrow): explicitly whitelists only the cluster-scoped
  kinds named in `var.platform_cluster_resource_whitelist` (CRDs, `ClusterRole`,
  `ClusterRoleBinding` by default).
- Each project is backed by its own `ApplicationSet` using a git directory generator
  (`apps/*` / `platform/*` in the GitOps repo). The generated `Application`'s `project` field is
  hard-coded per tier (never templated from generator output) so a directory placed under
  `apps/*` can never land in the `platform` project.
- Generated `Application` names are tier-prefixed (`apps-<dir>` / `platform-<dir>`) to avoid a
  future cross-tier name collision.
- `sync_policy.preserve_resources_on_deletion = true` on both `ApplicationSet`s prevents an
  accidental directory deletion/rename in the GitOps repo from cascade-deleting live resources.

## Input

```hcl
module "argocd_gitops" {
  source = "../../../modules/argocd-gitops"

  gitops_repo_url             = "git@github.com:org/gitops-repo.git"
  gitops_repo_ssh_private_key = local.secrets.gitops_repo_ssh_private_key

  apps_destination_namespaces     = ["arc-runners"]
  platform_destination_namespaces = ["arc-systems", "kube-system"]
}
```

## Provider authentication

The `argocd` provider authenticates via `port_forward_with_namespace` against the existing
cluster kubeconfig (not an exposed hostname), using ArgoCD's auto-generated
`argocd-initial-admin-secret`. See `environments/staging/argocd-gitops/terragrunt.hcl` for the
`before_hook` that fetches this password into a git-ignored local file before each
plan/apply/refresh/import.

A dedicated least-privilege `terraform` ArgoCD account (instead of the bootstrap admin account)
is intentionally deferred -- see the origin plan's Key Technical Decisions #8 and
Deferred to Follow-Up Work.
