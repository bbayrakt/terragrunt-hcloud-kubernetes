# Hetzner Kubernetes with Terragrunt

Deploys a Talos Linux cluster on Hetzner Cloud using the [terraform-hcloud-kubernetes](https://github.com/hcloud-k8s/terraform-hcloud-kubernetes) Terraform module, installs additional Helm charts with CRD management and sets up Gateway API with a HCloud load balancer.

The idea is to be able to provide one Terragrunt project which can deploy the cluster, install cluster components and provide end-to-end configuration and upgrades for the entire cluster.

## Repository layout

This repo hosts both the Terraform/Terragrunt infrastructure (under `infra/`) and, at the true
repo root, the `apps/`/`platform/` content ArgoCD syncs as the GitOps source for everything
beyond the bootstrap charts (see `docs/gitops-repo-scaffold.md`).

```text
.
├── .gitignore
├── .sops.yaml
├── AGENTS.md
├── README.md
├── apps/
│   └── README.md
├── platform/
│   ├── README.md
│   ├── arc-systems/
│   ├── arc-runners/
│   └── sealed-secrets/
├── docs/
│   ├── brainstorms/
│   ├── plans/
│   ├── solutions/
│   └── gitops-repo-scaffold.md
└── infra/
    ├── keys.txt
    ├── root.hcl
    ├── secrets.yaml
    ├── secrets.yaml.example
    ├── environments/
    │   ├── production/
    │   │   ├── env.hcl
    │   │   ├── crds/
    │   │   │   └── terragrunt.hcl
    │   │   ├── gateway-api/
    │   │   │   └── terragrunt.hcl
    │   │   ├── helm-charts/
    │   │   │   └── terragrunt.hcl
    │   │   └── kubernetes-cluster/
    │   │       └── terragrunt.hcl
    │   └── staging/
    │       ├── env.hcl
    │       ├── kubeconfig-staging
    │       ├── kubeconfig-staging.bak
    │       ├── talosconfig-staging
    │       ├── talosconfig-staging.bak
    │       ├── argocd-gitops/
    │       │   └── terragrunt.hcl
    │       ├── crds/
    │       │   └── terragrunt.hcl
    │       ├── gateway-api/
    │       │   └── terragrunt.hcl
    │       ├── helm-charts/
    │       │   └── terragrunt.hcl
    │       ├── karpenter/
    │       │   └── terragrunt.hcl
    │       └── kubernetes-cluster/
    │           ├── talosconfig-staging
    │           └── terragrunt.hcl
    ├── examples/
    │   ├── README.md
    │   ├── gateway-api-example.yaml
    │   ├── minio-backend/
    │   │   ├── .env.example
    │   │   ├── README.md
    │   │   ├── backend.tf
    │   │   └── docker-compose.yaml.example
    │   └── seaweedfs-backend/
    │       ├── README.md
    │       ├── backend.tf
    │       ├── docker-compose.yaml.example
    │       └── s3.json.example
    └── modules/
        ├── argocd-gitops/
        │   ├── README.md
        │   ├── main.tf
        │   ├── outputs.tf
        │   └── variables.tf
        ├── crds/
        │   ├── main.tf
        │   └── variables.tf
        ├── gateway-api/
        │   ├── README.md
        │   ├── main.tf
        │   ├── outputs.tf
        │   └── variables.tf
        ├── helm-charts/
        │   ├── README.md
        │   ├── main.tf
        │   ├── outputs.tf
        │   └── variables.tf
        └── karpenter/
            ├── main.tf
            ├── outputs.tf
            └── variables.tf
```

## Prerequisites

Install and configure:

- `terraform`
- `terragrunt`
- `sops`
- `age` (`age-keygen`)
- `kubectl`
- `helm`

You also need:

- A Hetzner Cloud API token
- S3-compatible backend credentials (SeaweedFS / MinIO / similar)
- Cloudflare API token (if using ExternalDNS)
- A domain for Gateway API / cert-manager

## Quick start

From `infra/`, generate an AGE key pair and export it for SOPS:

```bash
cd infra
age-keygen -o keys.txt
export SOPS_AGE_KEY_FILE="$(pwd)/keys.txt"
```

Update `.sops.yaml`'s `age:` recipient (repo root) with the public key `age-keygen` printed above.

If `secrets.yaml` is missing, create it from template and encrypt it (from `infra/`):

```bash
cp secrets.yaml.example secrets.yaml
sops -e -i secrets.yaml
```

Edit secrets anytime (from `infra/`):

```bash
sops secrets.yaml
```

## Deployment order

For each environment (`staging` or `production`), apply modules in this order:

1. `kubernetes-cluster` (staging creates the control plane only)
2. `crds`
3. `karpenter` (staging only: controller, Talos worker Secret, HCloudNodeClass, and NodePool)
4. `helm-charts` (bootstrap-only charts: ArgoCD, ExternalDNS -- everything else is ArgoCD-managed, see below)
5. `argocd-gitops` (staging only: configures ArgoCD via Terraform -- `AppProject`s, `ApplicationSet`s, and the GitOps repository registration -- so it deploys everything else)
6. `gateway-api`

Everything beyond the bootstrap charts (`argocd`, `external-dns`, `karpenter`) is deployed by
ArgoCD from this same repository's top-level `apps/`/`platform/` directories, not by Terraform.
See `docs/plans/2026-07-30-001-feat-argocd-gitops-migration-plan.md`,
`docs/brainstorms/argocd-gitops-migration-requirements.md`'s 2026-08-01 amendment, and
`docs/gitops-repo-scaffold.md` for the full design and required conventions.

### One-command apply/destroy (recommended)

Each stack's `terragrunt.hcl` declares its dependencies (`dependencies { paths = [...] }` and, where
outputs are consumed, `dependency "kubernetes_cluster" { ... mock_outputs ... }`) so Terragrunt's
whole-environment commands sequence every stack correctly without any manual per-stack ordering:

```bash
cd infra/environments/staging   # or production
terragrunt apply --all          # applies in the order above; add --non-interactive to skip prompts
terragrunt destroy --all        # destroys in exact reverse order
terragrunt plan --all           # plan-only, safe to run any time
```

Notes:
- This repo's pinned Terragrunt version removed `terragrunt run-all <cmd>` with no backward-compat
  shim; use the `<cmd> --all` form shown above (equivalently `terragrunt run --all <cmd>`).
- No resource in this repo carries a `prevent_destroy` lifecycle guard (removed 2026-08-02, a
  deliberate choice to keep `destroy --all` a genuine one-command full teardown) -- review
  `terragrunt plan --all` output before applying if you're not intending a full teardown, since a
  config change that happens to touch a CRD or a shared secret's namespace will now destroy it
  silently instead of erroring loudly.
- `dependency "kubernetes_cluster" { mock_outputs = ... }` blocks let Terragrunt resolve every
  downstream stack's config even when `kubernetes-cluster` has no state yet (fresh environment) or
  no longer has state (already destroyed) -- the mock is only ever used when the real dependency
  output is genuinely unavailable; a live, applied cluster's real outputs always take precedence.
- After a full `destroy --all`, also remove the environment's now-stale local kubeconfig/talosconfig
  files (`infra/environments/<env>/kubeconfig*`, `talosconfig*`) -- Terraform/Terragrunt state is
  clean at that point, but these local files are separate artifacts the cluster module doesn't
  clean up on destroy, and a stale kubeconfig can cause a confusing connection-timeout error on the
  next `plan`/`apply` before the fresh cluster's own kubeconfig is written.

### Manual per-stack sequence (for granular control)

Example (`staging`, from `infra/`):

```bash
cd infra/environments/staging/kubernetes-cluster && terragrunt init -reconfigure && terragrunt apply
cd ../crds && terragrunt init -reconfigure && terragrunt apply
cd ../karpenter && terragrunt init -reconfigure && terragrunt apply
cd ../helm-charts && terragrunt init -reconfigure && terragrunt apply
cd ../argocd-gitops && terragrunt init -reconfigure && terragrunt apply
cd ../gateway-api && terragrunt init -reconfigure && terragrunt apply
```

## Validation workflow (required)

Run from the true repository root:

```bash
export SOPS_AGE_KEY_FILE="$(git rev-parse --show-toplevel)/infra/keys.txt"
terragrunt hcl format
terragrunt hcl validate
```

Then validate changed stack(s) (from `infra/`):

```bash
cd infra/environments/<env>/<module>
terragrunt init -reconfigure
terragrunt validate
```

Environment-specific checks:

```bash
cd infra/environments/staging/kubernetes-cluster && terragrunt validate
cd infra/environments/production/kubernetes-cluster && terragrunt validate
cd infra/environments/staging/gateway-api && terragrunt validate
cd infra/environments/production/gateway-api && terragrunt validate
```

## Notes

- Keep secrets only in `infra/secrets.yaml`; never hardcode credentials in HCL/Terraform.
- `infra/root.hcl` configures S3-compatible remote state from decrypted secrets.
- `gateway-api` depends on cluster + CRDs + helm charts; apply it last.
- Some Terragrunt configs use deterministic fallbacks for static-safe validation when dependency outputs are unavailable.
