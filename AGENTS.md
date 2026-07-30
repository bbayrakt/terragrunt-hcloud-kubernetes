# AGENTS.md

## Scope
These instructions apply to the entire repository.

## Validation prerequisites
- Export SOPS key before any Terragrunt validation command:
  - `export SOPS_AGE_KEY_FILE="$(git rev-parse --show-toplevel)/keys.txt"`
- Run all commands from the repository root unless noted.

## Required validation workflow
1. Format Terragrunt HCL:
   - `terragrunt hcl format`
2. Validate Terragrunt HCL:
   - `terragrunt hcl validate`
3. Validate module-level Terraform/Terragrunt config for changed stack(s):
  - `cd environments/<env>/<module> && terragrunt init -reconfigure && terragrunt validate`

## Environment-specific checks
Only run checks if changes are made in the corresponding module.
- Staging cluster:
  - `cd environments/staging/kubernetes-cluster && terragrunt validate`
- Production cluster:
  - `cd environments/production/kubernetes-cluster && terragrunt validate`
- Staging gateway:
  - `cd environments/staging/gateway-api && terragrunt validate`
- Production gateway:
  - `cd environments/production/gateway-api && terragrunt validate`

## Notes
- If a dependency output is unavailable during `terragrunt hcl validate`, use deterministic local fallbacks in Terragrunt expressions so validation remains static-safe.
- Do not hardcode secrets in HCL/Terraform files; keep secrets in `secrets.yaml` and decrypt via SOPS.