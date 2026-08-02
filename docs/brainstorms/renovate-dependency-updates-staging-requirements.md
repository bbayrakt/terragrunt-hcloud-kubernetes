---
date: 2026-08-02
topic: renovate-dependency-updates-staging
---

# Renovate-Managed Dependency Updates for Staging (Terraform + ArgoCD)

## Problem Frame

Component versions in this repo are pinned by hand in at least five distinct shapes, spread
across Terraform, Terragrunt, and ArgoCD-managed Helm content: Terraform provider constraints
generated inside `terragrunt.hcl` `generate` block heredocs; an external Terraform module pinned
by git ref, itself set indirectly via a `kubernetes_module_version` local in `env.hcl` and
interpolated into `terragrunt.hcl`'s `source`; plain Terraform-managed Helm chart versions inside
`env.hcl`'s `helm_charts` map (e.g. `argocd`, `external-dns`) and standalone version inputs (e.g.
`karpenter_chart_version`); and Helm chart dependency versions in `platform/*/Chart.yaml` wrapper
charts that ArgoCD syncs. Nothing currently flags when any of these fall behind upstream, so the
sole operator has to remember to manually audit several different file shapes on no fixed
schedule. Staging and production have already drifted as a result (staging's
`kubernetes_module_version` is `5.3.0` vs production's `3.21.3`), and there's no forcing function
today that would surface a stale or vulnerable pin.

---

## Requirements

**Tool and installation**
- R1. Install the hosted Renovate GitHub App on this repository, granted access scoped to this
  repo.
- R2. Add a Renovate config (e.g. `.github/renovate.json`) whose scope for v1 covers only
  staging-scoped files: `infra/environments/staging/**` (all six stacks' `terragrunt.hcl` files
  plus `env.hcl`) and `platform/**/Chart.yaml` (extending to `apps/**/Chart.yaml` once that
  directory holds real applications).

**Coverage**
- R3. The config must detect and propose bumps for, at minimum, every version-pin shape that
  exists in staging today: Terraform provider version constraints inside `terragrunt.hcl` generate
  blocks; the `kubernetes_module_version` git-ref pin in `staging/env.hcl` (via a custom regex
  manager, since it's consumed indirectly through Terragrunt interpolation rather than a literal
  `source` string); the `helm_charts` map's per-chart `version` strings in `staging/env.hcl`
  (`external-dns`, `argocd`) and `karpenter_chart_version`, both via custom regex managers; and
  `platform/*/Chart.yaml` Helm chart dependency versions via Renovate's native Helm manager.
- R4. Production's Terraform stacks and `env.hcl` are explicitly excluded from Renovate's scope
  for v1.

**Grouping and cadence**
- R5. Bump PRs are grouped by category rather than opened per-dependency or left at tool defaults:
  one PR for Terraform provider bumps, one for the external module git-ref bump, one for
  Terraform-managed Helm chart versions (the `helm_charts` map plus `karpenter_chart_version`),
  and one for ArgoCD-managed `Chart.yaml` dependency bumps.
- R6. Renovate checks for and opens grouped PRs on a weekly schedule.

**Merge policy**
- R7. No auto-merge is configured for any bump category; every PR requires manual review and
  manual merge, regardless of how minor the version change appears.

**CI validation**
- R8. Add a GitHub Actions workflow, triggered on pull requests touching
  `infra/environments/staging/**` or `infra/modules/**`, that runs `terragrunt hcl format`
  (check mode), `terragrunt hcl validate`, and `terragrunt init -reconfigure && terragrunt
  validate` for each affected staging stack in dependency order.
- R9. The workflow decrypts `infra/secrets.yaml` using a SOPS age private key stored as a GitHub
  Actions secret, so `terragrunt validate` (which reads `env.hcl`'s `sops_decrypt_file` call)
  succeeds in CI the same way it does locally.
- R10. The new CI workflow's own GitHub Actions (checkout, Terraform/Terragrunt setup actions,
  etc.) are included in Renovate's `github-actions` coverage so the workflow itself doesn't go
  stale.

---

## Success Criteria

- Weekly, the operator receives a small, category-grouped set of PRs (not one per dependency)
  covering every version-pin shape that exists in staging today, instead of having to remember to
  check five different files by hand.
- Each bump PR shows a passing or failing CI validate check before the operator decides whether to
  merge, without first having to run the manual validation workflow locally.
- No PR ever merges without explicit operator action.
- Production stays completely unaffected by this work until it is explicitly brought into scope in
  a follow-up (after its GitOps migration lands).

---

## Scope Boundaries

- Production's Terraform stacks and `env.hcl` are out of scope until the ArgoCD GitOps migration
  (`docs/brainstorms/argocd-gitops-migration-requirements.md`) lands there.
- No auto-merge for any dependency category in v1.
- Self-hosting Renovate via a repo-owned Actions workflow is out of scope; the hosted GitHub App
  is used instead.
- Broader CI beyond validate-level checks (e.g. `terragrunt plan` on PRs, drift detection, apply
  automation) is out of scope.
- Renovate's `github-actions` coverage is limited to the new CI workflow's own action pins; no
  repo-wide GitHub Actions inventory work is implied.
- Container image tags that might exist inside chart `values.yaml` beyond what wrapper
  `Chart.yaml` files expose are out of scope unless planning discovers they need equivalent
  pinning treatment.

---

## Key Decisions

- **Renovate over Dependabot**: this repo's version pins live in shapes Dependabot's `terraform`
  ecosystem doesn't discover — an arbitrarily-named `env.hcl` holding plain version strings in an
  `inputs` map, and a module git-ref set indirectly through Terragrunt local interpolation rather
  than a literal `source` string. Renovate's native `terragrunt` manager plus custom regex managers
  cover both, alongside its native `helm` and `github-actions` managers for the rest. Dependabot's
  April 2025 Helm-ecosystem support and confirmed parsing of `terragrunt.hcl` generate blocks
  narrowed the gap but didn't close it.
- **Staging-only v1 scope**: production has no `argocd-gitops` or `karpenter` stack yet and is
  intentionally trailing staging's module version. Including it now risks proposing bumps to a
  stack that's about to be restructured by the already-in-flight GitOps migration.
- **Manual merge for every category**: this repo has no `prevent_destroy` lifecycle guards
  anywhere (removed deliberately), so no bump is treated as safe enough to auto-merge, however
  minor it looks.
- **CI validation added alongside the bot**: without it, a bump PR would carry no automated signal
  at all beyond Renovate's own config being valid.
- **Hosted Renovate GitHub App over self-hosted**: accepted trade-off of granting a third-party app
  repo access in exchange for zero ongoing workflow-maintenance burden.

---

## Dependencies / Assumptions

- Assumes repo admin/owner permission to install the Renovate GitHub App.
- Assumes a SOPS age keypair can be provided to CI for decryption without weakening the current
  security model beyond what's acceptable — a CI-scoped keypair limited to what staging's
  `secrets.yaml` needs, distinct from the operator's personal `infra/keys.txt`, may be preferable
  (left for planning to decide).
- Assumes the production GitOps migration described in
  `docs/brainstorms/argocd-gitops-migration-requirements.md` remains the intended path; if that
  plan changes materially, production's exclusion here should be revisited.
- Assumes staging's `helm_charts` map and `karpenter_chart_version` keep their current plain-string
  form; if that config is refactored elsewhere, the custom regex manager patterns will need
  updating to match.

---

## Outstanding Questions

### Deferred to Planning

- [Affects R3][Technical] Exact Renovate custom regex manager patterns for the interpolated
  `kubernetes_module_version` local and the `helm_charts` map version strings in `env.hcl`.
- [Affects R8][Technical] Exact stack apply/validate order the CI workflow should run, mirroring
  README's existing "Required validation workflow" section.
- [Affects R9][Needs research] Whether to mint a dedicated CI-only age keypair (narrower blast
  radius, recommended) vs. reusing the existing key, and how to add a second `.sops.yaml`
  recipient without manually re-encrypting `secrets.yaml`.
- [Affects R2][Technical] Whether Renovate's managers need explicit `fileMatch`/path scoping to
  avoid also matching production's files, since both environments share the
  `infra/environments/**` tree.

---

## Next Steps

-> `/ce-plan` for structured implementation planning
