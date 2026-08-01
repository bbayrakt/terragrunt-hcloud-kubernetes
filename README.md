# Hetzner Kubernetes with Terragrunt

Deploys a Talos Linux cluster on Hetzner Cloud using the [terraform-hcloud-kubernetes](https://github.com/hcloud-k8s/terraform-hcloud-kubernetes) Terraform module, installs additional Helm charts with CRD management and sets up Gateway API with a HCloud load balancer.

The idea is to be able to provide one Terragrunt project which can deploy the cluster, install cluster components and provide end-to-end configuration and upgrades for the entire cluster.

## Repository layout

```text
.
├── .gitignore
├── .sops.yaml
├── AGENTS.md
├── Makefile
├── README.md
├── keys.txt
├── root.hcl
├── secrets.yaml
├── secrets.yaml.example
├── setup.sh
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
    └── kubernetes-cluster/
        ├── README.md
        ├── kubernetes.tf
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

From repository root:

```bash
./setup.sh
```

Then ensure your SOPS key is exported (required before validation commands):

```bash
export SOPS_AGE_KEY_FILE="/home/berk/hetznerk8s/keys.txt"
```

If `secrets.yaml` is missing, create it from template and encrypt it:

```bash
cp secrets.yaml.example secrets.yaml
sops -e -i secrets.yaml
```

Edit secrets anytime:

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
ArgoCD from a separate, dedicated GitOps repository, not by Terraform. See
`docs/plans/2026-07-30-001-feat-argocd-gitops-migration-plan.md` and
`docs/gitops-repo-scaffold.md` for the full design and the GitOps repo's required conventions.

Example (`staging`):

```bash
cd environments/staging/kubernetes-cluster && terragrunt init -reconfigure && terragrunt apply
cd ../crds && terragrunt init -reconfigure && terragrunt apply
cd ../karpenter && terragrunt init -reconfigure && terragrunt apply
cd ../helm-charts && terragrunt init -reconfigure && terragrunt apply
cd ../argocd-gitops && terragrunt init -reconfigure && terragrunt apply
cd ../gateway-api && terragrunt init -reconfigure && terragrunt apply
```

## Validation workflow (required)

Run from repository root:

```bash
export SOPS_AGE_KEY_FILE="/home/berk/hetznerk8s/keys.txt"
terragrunt hcl format
terragrunt hcl validate
```

Then validate changed stack(s):

```bash
cd environments/<env>/<module>
terragrunt init -reconfigure
terragrunt validate
```

Environment-specific checks:

```bash
cd environments/staging/kubernetes-cluster && terragrunt validate
cd environments/production/kubernetes-cluster && terragrunt validate
cd environments/staging/gateway-api && terragrunt validate
cd environments/production/gateway-api && terragrunt validate
```

## Common Make targets

```bash
make setup
make edit-secrets
make view-secrets

make plan ENV=staging MODULE=kubernetes-cluster
make apply ENV=staging MODULE=kubernetes-cluster
make validate ENV=staging MODULE=gateway-api
```

## Notes

- Keep secrets only in `secrets.yaml`; never hardcode credentials in HCL/Terraform.
- `root.hcl` configures S3-compatible remote state from decrypted secrets.
- `gateway-api` depends on cluster + CRDs + helm charts; apply it last.
- Some Terragrunt configs use deterministic fallbacks for static-safe validation when dependency outputs are unavailable.
