# AGENTS.md

## Scope
These instructions apply to the entire repository.

## Repository layout
- `infra/` contains all Terraform/Terragrunt content (`environments/`, `modules/`, `root.hcl`,
  `examples/`, `secrets.yaml`, `secrets.yaml.example`, `keys.txt`).
- `apps/`, `platform/`, `docs/`, `.sops.yaml`, `README.md`, and this file remain at the true
  repository root — they are not part of `infra/`.

## Validation prerequisites
- Export SOPS key before any Terragrunt command (validation, plan, apply, or destroy):
  - `export SOPS_AGE_KEY_FILE="$(git rev-parse --show-toplevel)/infra/keys.txt"`
- Run Terragrunt/Terraform commands from within `infra/` (e.g. `cd infra/environments/<env>/<module>`);
  repository-wide commands like `terragrunt hcl format`/`validate` or `git`/`sops` invocations run
  from the true repository root.

## Deployment workflow
No `Makefile`/`setup.sh` in this repo (removed 2026-08-02, deliberately -- use the raw commands
below). Always export `SOPS_AGE_KEY_FILE` first (see Validation prerequisites above).

**Single stack** (from `infra/environments/<env>/<module>`):
```bash
terragrunt init -reconfigure
terragrunt plan
terragrunt apply     # or: terragrunt destroy
```

**Whole environment, one command** (from `infra/environments/<env>`, `env` = `staging` or
`production`) -- Terragrunt sequences every stack automatically via each `terragrunt.hcl`'s
`dependencies {}`/`dependency {}` blocks: forward (documented deployment order in `README.md`) for
`apply`, exact reverse for `destroy`:
```bash
terragrunt plan --all
terragrunt apply --all      # add --non-interactive to skip the confirmation prompt
terragrunt destroy --all
```
This repo's pinned Terragrunt version removed `terragrunt run-all <cmd>` with no backward-compat
shim -- use the `<cmd> --all` form above (equivalently `terragrunt run --all <cmd>`).

No resource in this repo carries a `prevent_destroy` lifecycle guard (removed 2026-08-02, so
`destroy --all` is a genuine one-command full teardown that leaves state clean without any manual
`terraform state rm` disowning step) -- review `plan`/`plan --all` output before applying if you're
not intending a full teardown, since a config change touching a CRD or a shared secret's namespace
now destroys it silently instead of erroring loudly.

`apply --all`/`destroy --all`/`plan --all` only work correctly once `kubernetes-cluster` is already
applied (a live cluster) -- running them against a stack with no cluster yet fails with a
dependency-resolution error (accepted, not a priority to fix). After a full `destroy --all`, also
remove the environment's now-stale local `kubeconfig*`/`talosconfig*` files under
`infra/environments/<env>/` -- Terraform/Terragrunt state is clean at that point, but these local
files are separate artifacts the cluster module doesn't clean up on destroy, and a stale one causes
a confusing connection-timeout error on the next `plan`/`apply` before a fresh cluster's own
kubeconfig is written.

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

## Automated CI validation (staging)

PRs touching `infra/environments/staging/**` or `infra/modules/**` trigger
`.github/workflows/terragrunt-validate.yml`, which runs the same validation steps as the
Required validation workflow above:

- **lint job** (ungated, no secret access): `terragrunt hcl format --check` + `terragrunt hcl
  validate` at repo root.
- **validate job** (approval-gated): `terragrunt init -reconfigure && terragrunt validate --all`
  from `infra/environments/staging/`, using a dedicated CI-only SOPS age key. Runs inside the
  GitHub Environment `ci-secrets-staging` (required reviewers, "Prevent self-review" enabled).

## Notes
- If a dependency output is unavailable during `terragrunt hcl validate`, use deterministic local fallbacks in Terragrunt expressions so validation remains static-safe.
- Do not hardcode secrets in HCL/Terraform files; keep secrets in `infra/secrets.yaml` and decrypt via SOPS.
- Documented solutions to past problems (bugs, patterns, tooling decisions) live in `docs/solutions/`, organized by category with YAML frontmatter (`module`, `tags`, `problem_type`) — relevant when implementing or debugging in areas that may have been documented before.
- This repo self-hosts its own ArgoCD GitOps content (`apps/`, `platform/` at the true root) — see `README.md`'s Deployment Order section, `infra/modules/argocd-gitops/README.md` for the module's configurable path/auth-mode variables (`gitops_apps_path`/`gitops_platform_path`, three credential modes), and `apps/README.md`/`platform/README.md` for the tiering convention.