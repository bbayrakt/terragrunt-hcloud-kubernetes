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

## Automated dependency updates (staging) and CI validation

### Renovate (hosted GitHub App)

Staging's dependency versions are managed by the hosted Renovate GitHub App on a **weekly
schedule**, with bump PRs **grouped by category** and **no auto-merge** — every PR requires manual
review and merge. See [docs/brainstorms/renovate-dependency-updates-staging-requirements.md](docs/brainstorms/renovate-dependency-updates-staging-requirements.md)
for the rationale, and `.github/renovate.json` for the config.

Scope (v1):

- `infra/environments/staging/**` — Terraform provider constraints in `generate` blocks,
  `kubernetes_module_version` git ref, `helm_charts` map versions, `karpenter_chart_version`,
  `external_dns_version`.
- `platform/**/Chart.yaml` (and future `apps/**/Chart.yaml`) — ArgoCD-managed Helm chart
dependencies.
- `.github/workflows/*.yml` — the CI workflow's own GitHub Actions (`github-actions` manager).
- Production (`infra/environments/production/**`) is **explicitly excluded** from v1 scope.

Bump PRs are grouped into four categories: **Terraform providers**, **external module ref**
(`kubernetes_module_version`), **Terraform-managed Helm charts**, and **ArgoCD-managed Helm
charts**.

> ⚠️ **ArgoCD-managed chart bumps deploy on merge.** `platform/`/`apps/` `Chart.yaml` bumps are
> picked up by ArgoCD's `ApplicationSet` (`automated { prune: true }` sync policy) on its next
> reconcile — there is **no separate `terragrunt apply` gate** for this category, unlike the other
> three (which all require the operator to run `terragrunt apply` after merge). Review these PRs
> with equal or greater scrutiny, and spot-check with `helm template` before merging.

### CI workflow (`.github/workflows/terragrunt-validate.yml`)

Every PR touching `infra/environments/staging/**` or `infra/modules/**` runs the existing manual
validation sequence as two jobs:

1. **lint** (ungated, no secrets): `terragrunt hcl format --check` + `terragrunt hcl validate`
   from the repo root.
2. **validate** (approval-gated): `terragrunt init -reconfigure && terragrunt validate --all`
   from `infra/environments/staging/`, using a dedicated **CI-only SOPS age key**.

The validate job runs inside the GitHub **environment `ci-secrets-staging`**, which has
**required reviewers** configured — a human must approve the run before it starts. This closes the
code-execution-before-review gap: Terragrunt evaluates `generate`/`before_hook` blocks as ordinary
config parsing, so without this gate a PR-supplied hook could exfiltrate decrypted secrets before
anyone reviewed the diff. The `SOPS_AGE_KEY` secret is an **environment secret** bound to
`ci-secrets-staging` (not a repository secret), so no other job in the repo can read it, and
"Prevent self-review" is enabled so the PR author can't approve their own run.

> ⚠️ The required-reviewer environment protection is **public-repo-only** on GitHub's Free/Pro/Team
> plans and is silently ignored if this repository is ever made private. Re-verify the gate is
> still active if repo visibility ever changes.

### CI-only SOPS age key (blast radius)

`.sops.yaml` has **two age recipients** for `infra/secrets.yaml`: the operator's personal key
(`infra/keys.txt`) and a dedicated CI key (private key stored only as the `SOPS_AGE_KEY` GitHub
environment secret). The CI key can decrypt the **full shared `infra/secrets.yaml`** — there is
one file and one recipient rule for both staging and production. In concrete terms, the CI key
can read: the Hetzner Cloud API token (account control), the Cloudflare API token, the GitOps
repository's SSH deploy key (write access into the GitOps repo), SeaweedFS/S3 credentials, and the
platform-tier SOPS age key (which itself decrypts `platform/` KSOPS secrets). This residual
blasting radius is bounded by the approval gate above — the key is only reachable after a human
approves a specific run — and by the key being independently revocable without touching the
operator's own key.

**Recipient rotation runbook (standing procedure):** whenever `.sops.yaml`'s recipient list
changes (rotating the CI key, rotating the operator's key, or a future per-environment secrets
split), re-run `sops updatekeys` against `infra/secrets.yaml` for the **current full recipient
set** and re-verify decrypt with every remaining key. Recipient metadata is baked into the
encrypted file at `updatekeys` time, not re-derived from `.sops.yaml` on every edit — a skipped
`updatekeys` run fails silently (the file keeps decrypting for whoever was already embedded, with
no error signaling that a newly-declared recipient is locked out).

Note: `infra/modules/karpenter/terraform.tf`'s Renovate coverage is deliberately scoped to staging
paths (via `.github/renovate.json`'s `terraform` manager `fileMatch`) rather than left on
Renovate's default `**/*.tf` match, so it doesn't silently start touching production once
production adopts the `karpenter` stack.

## Notes

- Keep secrets only in `infra/secrets.yaml`; never hardcode credentials in HCL/Terraform.
- `infra/root.hcl` configures S3-compatible remote state from decrypted secrets.
- `gateway-api` depends on cluster + CRDs + helm charts; apply it last.
- Some Terragrunt configs use deterministic fallbacks for static-safe validation when dependency outputs are unavailable.
