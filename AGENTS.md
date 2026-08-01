# AGENTS.md

## Scope
These instructions apply to the entire repository.

## Repository layout
- `infra/` contains all Terraform/Terragrunt content (`environments/`, `modules/`, `root.hcl`,
  `Makefile`, `setup.sh`, `examples/`, `secrets.yaml`, `secrets.yaml.example`, `keys.txt`).
- `apps/`, `platform/`, `docs/`, `.sops.yaml`, `README.md`, and this file remain at the true
  repository root — they are not part of `infra/`.

## Validation prerequisites
- Export SOPS key before any Terragrunt validation command:
  - `export SOPS_AGE_KEY_FILE="$(git rev-parse --show-toplevel)/infra/keys.txt"`
- Run Terragrunt/Terraform commands from within `infra/` (e.g. `cd infra/environments/<env>/<module>`,
  or `make -C infra <target>`); repository-wide commands like `terragrunt hcl format`/`validate`
  or `git`/`sops` invocations run from the true repository root.

## Required validation workflow
1. Format Terragrunt HCL:
   - `terragrunt hcl format`
2. Validate Terragrunt HCL:
   - `terragrunt hcl validate`
3. Validate module-level Terraform/Terragrunt config for changed stack(s):
  - `cd infra/environments/<env>/<module> && terragrunt init -reconfigure && terragrunt validate`

## Environment-specific checks
Only run checks if changes are made in the corresponding module.
- Staging cluster:
  - `cd infra/environments/staging/kubernetes-cluster && terragrunt validate`
- Production cluster:
  - `cd infra/environments/production/kubernetes-cluster && terragrunt validate`
- Staging gateway:
  - `cd infra/environments/staging/gateway-api && terragrunt validate`
- Production gateway:
  - `cd infra/environments/production/gateway-api && terragrunt validate`
- Staging ArgoCD GitOps:
  - `cd infra/environments/staging/argocd-gitops && terragrunt validate`

## Notes
- If a dependency output is unavailable during `terragrunt hcl validate`, use deterministic local fallbacks in Terragrunt expressions so validation remains static-safe.
- Do not hardcode secrets in HCL/Terraform files; keep secrets in `infra/secrets.yaml` and decrypt via SOPS.
- Documented solutions to past problems (bugs, patterns, tooling decisions) live in `docs/solutions/`, organized by category with YAML frontmatter (`module`, `tags`, `problem_type`) — relevant when implementing or debugging in areas that may have been documented before.
- This repo self-hosts its own ArgoCD GitOps content (`apps/`, `platform/` at the true root) — see `README.md`'s Deployment Order section, `infra/modules/argocd-gitops/README.md` for the module's configurable path/auth-mode variables (`gitops_apps_path`/`gitops_platform_path`, three credential modes), and `apps/README.md`/`platform/README.md` for the tiering convention.