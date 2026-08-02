---
title: "feat: Renovate dependency updates + CI validation for staging"
type: feat
status: active
date: 2026-08-02
origin: docs/brainstorms/renovate-dependency-updates-staging-requirements.md
deepened: 2026-08-02
---

# feat: Renovate dependency updates + CI validation for staging

## Overview

Install the hosted Renovate GitHub App, scoped to `infra/environments/staging/**` and the
ArgoCD-managed `platform/**` (and future `apps/**`) Helm content, so version bumps across all of
staging's distinct pin shapes surface automatically on a weekly cadence as a handful of
category-grouped PRs. Pair it with a new, minimal GitHub Actions workflow that runs the existing
manual validation workflow (`terragrunt hcl format`/`validate`, per-stack `terragrunt validate`)
on every PR touching staging or shared modules, so bump PRs carry a real signal before a human
reviews and manually merges them. Production is untouched by this work.

---

## Problem Frame

Version pins in this repo live in five distinct shapes with no forcing function to revisit any of
them: Terraform provider constraints generated inside `terragrunt.hcl` heredocs, an external
module pinned by git ref set indirectly through a `env.hcl` local, plain Terraform-managed Helm
chart versions inside `env.hcl`'s `helm_charts` map, a standalone `karpenter_chart_version` input,
and Helm chart dependency versions in `platform/*/Chart.yaml` wrapper charts synced by ArgoCD.
(A sixth, minor case — `infra/modules/karpenter/terraform.tf`'s `required_version` — exists too,
but is excluded from this count because it needs no dedicated handling; see Coverage Matrix.)
Staging and production have already drifted as a result (staging's `kubernetes_module_version` is
`5.3.0` vs production's `3.21.3`). See origin doc for full problem framing and the tool-choice
rationale (Renovate over Dependabot).

---

## Requirements Trace

**Installation & scope**
- R1. Install the hosted Renovate GitHub App on this repository.
- R2. Renovate config scoped to staging-only paths for v1 (`infra/environments/staging/**`,
  `platform/**/Chart.yaml`, future `apps/**/Chart.yaml`); production explicitly excluded.
- R4. Production's Terraform stacks and `env.hcl` are out of scope for v1.

**Version-pin coverage**
- R3. Coverage for every version-pin shape present in staging: Terraform provider constraints in
  `generate` blocks, the interpolated `kubernetes_module_version` git-ref pin, the `helm_charts`
  map's chart versions plus `karpenter_chart_version` and `external_dns_version`, and
  `platform/*/Chart.yaml` dependency versions.

**PR policy**
- R5. Bump PRs grouped by category (providers / module ref / Terraform-managed Helm charts /
  ArgoCD-managed Helm charts), not per-dependency or tool defaults.
- R6. Weekly check/PR cadence.
- R7. No auto-merge for any category; every PR requires manual review and merge.

**CI validation**
- R8. New GitHub Actions workflow runs `terragrunt hcl format`/`validate` plus per-stack
  `terragrunt validate` for staging on every relevant PR.
- R9. The workflow decrypts `infra/secrets.yaml` via a SOPS age key stored as a GitHub Actions
  secret.
- R10. The new CI workflow's own GitHub Actions are kept current via Renovate's `github-actions`
  coverage.

---

## Scope Boundaries

- Production's Terraform stacks and `env.hcl` are out of scope until the ArgoCD GitOps migration
  (`docs/brainstorms/argocd-gitops-migration-requirements.md`) lands there.
- No auto-merge for any dependency category.
- Self-hosting Renovate via a repo-owned Actions workflow is out of scope; the hosted GitHub App
  is used.
- CI is validate-level only — no `terragrunt plan` on PRs, no drift detection, no apply automation.
- Splitting `infra/secrets.yaml` into per-environment files (which would let a CI-scoped key
  decrypt only staging's secrets) is out of scope; see Risks & Dependencies for the accepted
  residual exposure.
- Live-cluster verification of a merged Helm chart bump (e.g. `helm template` re-render, RBAC-tier
  re-check per `docs/solutions/architecture-patterns/argocd-two-tier-rbac-boundary-and-arc-onboarding-2026-08-02.md`)
  is not automated by this work — `terragrunt validate` is static HCL/schema validation only and
  does not catch chart-render or ArgoCD-provider regressions.

### Deferred to Follow-Up Work

- Bringing production into Renovate/CI scope: separate follow-up once production adopts the
  `argocd-gitops`/`karpenter` stacks.

---

## Context & Research

### Relevant Code and Patterns

- `infra/environments/staging/{crds,gateway-api,helm-charts,karpenter,argocd-gitops}/terragrunt.hcl`
  — each has its own `generate "providers" { ... }` heredoc with plain-string version constraints;
  no shared/DRY provider generation exists at `infra/root.hcl`, so any provider-version coverage
  must target each stack file individually. `kubernetes-cluster/terragrunt.hcl` has no local
  `generate` block (constraints live inside the external module itself).
- `infra/environments/staging/env.hcl` — `locals.kubernetes_module_version` (interpolated into
  `kubernetes-cluster/terragrunt.hcl`'s `source = "...?ref=${include.env.locals.kubernetes_module_version}"`),
  `inputs.helm_charts.{external-dns,argocd}.version`, `inputs.karpenter_chart_version`,
  `inputs.external_dns_version`.
- `platform/{arc-runners,arc-systems,sealed-secrets,vpa}/Chart.yaml` — identical thin-wrapper
  pattern: `name: <chart>-wrapper`, fixed local `version: 0.1.0`, one `dependencies[0]` entry
  carrying the real upstream `version`/`repository`. `apps/` has no `Chart.yaml` yet (placeholder
  only).
- `infra/modules/karpenter/terraform.tf` — the only literal `.tf` file in the repo with a version
  constraint (`required_version = ">= 1.9.0"`); Renovate's `terraform` manager matches `**/*.tf` by
  default, so this one is already covered natively with zero config.
- `infra/root.hcl` — single shared `remote_state`/secrets-decrypt pattern
  (`sops_decrypt_file(find_in_parent_folders("secrets.yaml", "secrets.yaml.example"))`); every
  stack's `dependency` blocks already declare `mock_outputs_allowed_terraform_commands` including
  `"validate"`, so `terragrunt validate` works without a live cluster today — the new CI workflow
  can rely on this existing static-safe convention rather than adding new mocking.
- `.sops.yaml` (repo root) — a single active `creation_rules` entry, `path_regex: secrets\.yaml$`,
  one age recipient, applying to the one shared `infra/secrets.yaml` used by *both* staging and
  production `env.hcl`. No per-environment secrets split exists today.
- `.gitignore` — `keys.txt`, `kubeconfig*`, `talosconfig*`, `**/.argocd-admin-password` are all
  ignored; confirmed via `git check-ignore` that none of these are tracked. `infra/secrets.yaml`
  itself *is* tracked (ciphertext).
- README.md "Validation workflow (required)" and AGENTS.md "Required validation workflow" —
  verbatim source for the CI workflow's steps (`terragrunt hcl format`, `terragrunt hcl validate`,
  then per-stack `terragrunt init -reconfigure && terragrunt validate`). Note: AGENTS.md's
  environment-specific checklist includes "Staging ArgoCD GitOps"; README.md's equivalent list
  omits it — pre-existing discrepancy between the two files, not introduced by this plan.
- README.md "Deployment order" — `kubernetes-cluster → crds → karpenter → helm-charts →
  argocd-gitops → gateway-api`, matching each stack's `dependencies {}` graph.

### Institutional Learnings

- `docs/solutions/architecture-patterns/self-hosted-gitops-monorepo-migration-terragrunt-sops-state-preservation-2026-08-01.md`
  — `.sops.yaml` resolution walks upward from the encrypted file's directory (CI must run from a
  path where that upward walk still finds the root `.sops.yaml`); `set -e` does not protect a
  `X=$(cmd)` assignment from silently swallowing a failure — any CI step capturing command output
  should use an `if` condition instead; this repo's `try()`-wrapped-locals convention already makes
  `terragrunt validate` static-safe, so the CI workflow should lean on it rather than reinvent
  mocking.
- `docs/solutions/architecture-patterns/argocd-two-tier-rbac-boundary-and-arc-onboarding-2026-08-02.md`
  — ArgoCD's `ApplicationSet` template names releases `platform-{{path.basename}}` /
  `apps-{{path.basename}}` (prefixed, not the bare directory name); any Helm chart version bump
  should be spot-checked with `helm template <prefixed-release-name> <chart> --version <pin>`
  since `terragrunt validate` cannot catch chart-render or RBAC-tier regressions. If a bumped
  chart starts creating its own `Role`/`RoleBinding`, it must live in `platform/`, never `apps/`.
- `docs/solutions/integration-issues/terragrunt-apply-all-destroy-all-multi-stack-2026-08-02.md`
  — this repo's pinned Terragrunt version removed `run-all` with no shim; use `terragrunt <cmd>
  --all`. `mock_outputs_allowed_terraform_commands` already includes `"validate"` repo-wide per
  AGENTS.md convention, so `terragrunt validate --all` should work without extra mock changes.
- `docs/solutions/integration-issues/argocd-provider-config-path-tls-cert-verification-failure-2026-07-31.md`
  — reinforces that static HCL validation and live infrastructure/provider behavior are different
  guarantee classes in this repo; the new CI workflow's scope should be described accordingly (see
  Scope Boundaries).
- No prior CI/CD or Renovate-specific learning exists yet in `docs/solutions/` — this is new
  territory for the repo, worth a `/ce-compound` entry once this lands (see Documentation /
  Operational Notes).

### External References

- Renovate `terragrunt` manager (default `managerFilePatterns: ["/(^|/)terragrunt\\.hcl$/"]`) only
  extracts `terraform { source = ... }` module references, and only when the ref is a literal
  string (e.g. `?ref=v1.0.0`) — an interpolated ref like this repo's
  `?ref=${include.env.locals.kubernetes_module_version}` is not resolved by this manager natively.
- Renovate `terraform` manager (default `managerFilePatterns: ["**/*.tf", "**/*.tofu"]`) extracts
  `required_provider`/`provider`/`required_version`/`helm_release` depTypes, but does not match
  `.hcl` files by default.
- Renovate `helm` manager natively updates `Chart.yaml` `dependencies[].version` entries — covers
  all four `platform/*/Chart.yaml` files with zero custom config.
- Renovate `github-actions` manager natively covers action version pins inside
  `.github/workflows/*.yml`.
- Renovate `customManagers` (regex-based) can target arbitrary strings in arbitrary files via
  explicit `managerFilePatterns` + `matchStrings`, independent of filename conventions — the
  mechanism needed for `env.hcl`'s version strings and, pending verification, the provider
  constraints embedded in `terragrunt.hcl` generate-block heredocs.
- Dependabot's `terraform` ecosystem was independently confirmed (via a closed, resolved upstream
  issue) to parse provider versions inside Terragrunt `generate` block heredocs — this is a
  Dependabot-specific capability, not evidence about how Renovate's `terraform`/`terragrunt`
  managers behave on the same files. A hybrid (Dependabot for this one pin shape, Renovate for
  everything else) was considered and rejected: it would add a second bot's operational overhead
  to close uncertainty on a single category, when Renovate's necessity for the other four shapes
  (the interpolated module ref, `env.hcl`'s plain strings, OCI-hosted `karpenter_chart_version`,
  and `platform/*/Chart.yaml`) is unconditional regardless of how the provider-constraint category
  resolves — U3's per-stack `customManagers` fallback is the lower-overhead path if the native
  manager extension proves incomplete.
- GitHub Actions secrets are not exposed to `pull_request`-triggered workflow runs from forks by
  default (only `pull_request_target` exposes secrets to fork PRs) — irrelevant risk here since
  Renovate's GitHub App commits branches directly to this repo (not a fork), so the CI secret is
  available to Renovate's own PRs as required.

---

## Key Technical Decisions

- **Mint a dedicated CI-only SOPS age keypair** rather than reusing the operator's personal
  `infra/keys.txt`: add it as a second recipient on the single existing `.sops.yaml` creation rule
  (`age: <existing-recipient>,<ci-recipient>`), then run `sops updatekeys` on `infra/secrets.yaml`
  to re-encrypt for both recipients, and store only the CI keypair's private key as a GitHub
  Actions secret. Narrower blast radius and independently revocable without touching the
  operator's own key. *(Resolves the origin doc's deferred research question.)*
- **Accept that the CI key can decrypt the full shared `infra/secrets.yaml`**, including
  production's secrets, because there is only one file and one active creation rule
  (`path_regex: secrets\.yaml$`) covering both environments — splitting secrets per environment is
  a larger refactor and explicitly out of scope. Documented as a residual risk, not silently
  accepted.
- **CI validate command**: run from `infra/environments/staging/`, use `terragrunt validate --all`
  (this repo's pinned Terragrunt version removed `run-all`), after `terragrunt hcl format --check`
  and `terragrunt hcl validate` from the repo's true root — mirrors README/AGENTS.md's existing
  manual workflow rather than inventing a new one, and relies on the already-repo-standard
  `mock_outputs_allowed_terraform_commands` convention (already includes `"validate"`) instead of
  adding new mocking.
- **Provider-constraint coverage strategy, decided per stack, not as one blanket switch**: attempt
  to extend Renovate's built-in `terraform` manager's `managerFilePatterns` to also match staging's
  `terragrunt.hcl` files first (lowest config burden, reuses upstream provider-version parsing).
  The five `generate "providers"` heredocs are heterogeneous (1 provider in `gateway-api`/
  `argocd-gitops`, 2 in `crds`/`helm-charts`, 4 in `karpenter`), so a dry-run is more likely to
  produce **partial** extraction (clean for the simple 1-2-provider stacks, incomplete for
  `karpenter`'s denser block) than a uniform success/failure across all five. Evaluate per stack;
  for any stack where the fallback `customManagers` regex is needed, that stack's file must be
  **excluded** from the extended `terraform` manager's glob at the same time the fallback is added
  — leaving both active on the same file risks duplicate or conflicting patches to the identical
  heredoc line. Verification is deferred to implementation (see Open Questions) since it depends on
  observing Renovate's actual dry-run output against this repo's specific files.
- **ArgoCD-managed chart bumps are the highest-blast-radius category despite needing the least
  Renovate config**: `infra/modules/argocd-gitops/main.tf`'s `ApplicationSet`s use
  `syncPolicy.automated.prune = true`, so merging a `platform/*/Chart.yaml` (or future
  `apps/*/Chart.yaml`) version bump deploys to the live staging cluster on ArgoCD's next reconcile
  — no separate `terragrunt apply` gate exists, unlike the other three categories, which all
  require the operator to run `terragrunt apply` after merge before anything changes on-cluster.
  The "native, zero-config" framing of this category (see Coverage Matrix) describes Renovate
  config effort only, not review risk — reviewers should treat these PRs with equal or greater
  scrutiny than the Terraform-managed categories, not less.
- **Gate the CI workflow's secret-decrypting job behind a required-reviewer GitHub Environment,
  with the secret itself scoped to that environment** (not a plain repository secret): Terragrunt
  evaluates `generate`/`before_hook` blocks as ordinary config parsing, including for `validate` if
  a hook's `commands` list names it — so a branch-pushed PR (Renovate's own branches, or any other
  contributor's, since this repo isn't a fork-based workflow) could in principle add a
  `generate`/hook that exfiltrates decrypted secret material the moment CI runs, before any human
  reviews the diff. No-auto-merge (R7) and avoiding `pull_request_target` are merge-time and
  fork-boundary controls respectively; neither constrains what runs during the job itself. Routing
  the secret-bearing job through a GitHub Environment with required reviewers closes this gap by
  requiring an explicit human approval before that job executes for a given commit, independent of
  who pushed it — **but only if `SOPS_AGE_KEY` is created as an environment secret bound to that
  environment, not a repository secret**: a plain repository secret is readable by any job in any
  workflow regardless of whether it declares the gated environment, which would let a PR that adds
  a new ungated job or step read the key with no approval at all, silently reopening the exact gap
  this control exists to close. This mechanism is also a **v1 scope addition beyond the origin
  brainstorm's stated R8/R9** (which asked only for a validate-and-report CI signal) — added
  because deepening's security review surfaced a concrete exploit path the origin scope didn't
  anticipate, not because the user asked for a second approval mechanism on top of R7's
  no-auto-merge. It also depends on this repository remaining public: GitHub's required-reviewer
  environment protection is available on the Free/Pro/Team plans only for public repositories, and
  is silently ignored if the repository is ever converted to private — a dependency worth
  re-checking if that ever changes (see Risks & Dependencies). *(Added during plan deepening's
  security review; see U6.)*
- **`.sops.yaml` recipient changes require re-running `sops updatekeys`, and drift is silent**:
  recipient lists are baked into each encrypted file's own metadata at the time `updatekeys` (or
  initial encryption) runs, not re-derived from `.sops.yaml` on every edit. Minting the CI recipient
  now is a one-time `updatekeys` run, but any future recipient change (rotating the CI key, rotating
  the operator's key, or eventually splitting secrets per environment) must repeat that step for the
  full current recipient set, or the newly-declared recipient is silently locked out with no error
  signal. Documented as a standing operational runbook item (U5/U7), not just a point-in-time step.
- **`env.hcl` version strings require `customManagers`** regardless of the above, since neither
  built-in manager matches an arbitrarily-named file by default: one regex manager for
  `kubernetes_module_version` (datasource `github-tags`, package
  `hcloud-k8s/terraform-hcloud-kubernetes`), one for `helm_charts.{external-dns,argocd}.version`
  and `karpenter_chart_version`/`external_dns_version` (datasource `helm`, keyed by chart name and
  repository).
- **Every manager's file scope is explicitly restricted** to `infra/environments/staging/**`,
  `platform/**`, and (once populated) `apps/**` — never `infra/environments/production/**` — so
  production stays untouched without relying on Renovate's defaults. This restriction is applied
  even to `infra/modules/karpenter/terraform.tf`'s otherwise-native, zero-config `**/*.tf` match:
  that file is currently exposed only because `infra/modules/karpenter` happens to be sourced
  solely by staging today, and the "Deferred to Follow-Up Work" item below (production adopting
  the `karpenter`/`argocd-gitops` stacks) would silently make this same default glob start
  touching a file that governs production's next `terraform init`, with no Renovate config change
  to signal the transition. Scoping the `terraform` manager's file match explicitly to staging
  paths — rather than relying on the unscoped default for this one row — removes that dormant
  exposure instead of leaving it for a future audit to catch.

- **Renovate's scheduled runs should not begin until U6's CI workflow exists**: this plan's stated
  purpose for pairing a CI workflow with Renovate is so bump PRs "carry a real signal before a
  human reviews and manually merges them." Because U1-U4 (Renovate) and U5-U6 (CI) have no
  formal cross-dependency, implementing them out of order would let Renovate open unvalidated
  weekly bump PRs before any CI check exists. Treat U6 as a prerequisite for enabling Renovate's
  scheduled runs in practice, even though the units can be authored in any order.

### Coverage Matrix

| Pin shape | File(s) | Renovate mechanism | Status |
|---|---|---|---|
| Terraform provider constraints in `generate` blocks | `{crds,gateway-api,helm-charts,karpenter,argocd-gitops}/terragrunt.hcl` | `terraform` manager (extended `managerFilePatterns`) or per-stack `customManagers` fallback, mutually exclusive per stack | Needs per-stack dry-run verification |
| `karpenter/terraform.tf`'s `required_version` | `infra/modules/karpenter/terraform.tf` | `terraform` manager, explicitly scoped to staging paths rather than left on the unscoped default | Covered with one line of scoping config (see Key Technical Decisions) |
| External module git-ref (`kubernetes_module_version`) | `staging/env.hcl` | `customManagers` (`github-tags`) | Custom config required |
| Terraform-managed Helm chart versions (`helm_charts` map, `karpenter_chart_version`, `external_dns_version`) | `staging/env.hcl` | `customManagers` (`helm` datasource) | Custom config required |
| ArgoCD-managed Helm chart versions | `platform/*/Chart.yaml` (+ future `apps/*/Chart.yaml`) | `helm` manager (native) | Covered natively, no config needed |
| CI workflow's own actions | `.github/workflows/*.yml` | `github-actions` manager (native) | Covered natively once workflow exists |

"Native, no config needed" in this table describes Renovate config effort only. It does not imply
lower review risk — see the ArgoCD-managed-chart blast-radius decision above: that category
deploys immediately on merge via ArgoCD's `automated { prune: true }` sync policy, unlike the
other three categories.

---

## Open Questions

### Resolved During Planning

- Whether to mint a dedicated CI-only age keypair vs. reuse the existing one: mint dedicated (see
  Key Technical Decisions).
- Exact CI validate command sequence and stack order: `terragrunt hcl format --check` +
  `terragrunt hcl validate` at repo root, then `terragrunt validate --all` from
  `infra/environments/staging/` (dependency graph ordering handled automatically by Terragrunt).
- Whether `.sops.yaml`'s single shared rule blocks a staging-only CI key: yes, accepted as a
  documented residual risk rather than a blocker (splitting secrets per environment is out of
  scope for v1) — but see the expanded blast-radius wording added to Risks & Dependencies below;
  the exposure is reachable at CI-trigger time, not just "whatever staging happens to use."
- Whether the CI job needs a manual-approval gate before running against PR-supplied HCL: **yes**.
  Added during deepening's security review: Terragrunt's `generate`/`before_hook` mechanism can
  execute PR-supplied code with decrypt access before merge, which defeats no-auto-merge and
  non-`pull_request_target` as protections on their own. U6 now routes the secret-bearing job
  through a GitHub Environment requiring reviewer approval before it runs for a given commit — and
  the secret itself must be an *environment secret* bound to that environment, not a repository
  secret, or the gate provides no real protection (see Key Technical Decisions).
- Whether `terragrunt hcl format`/`terragrunt hcl validate` require `infra/secrets.yaml` decryption:
  **no** — these are pure HCL-syntax/schema checks and do not evaluate `env.hcl`'s
  `sops_decrypt_file` locals the way `terragrunt validate` does. U6 now splits the workflow into an
  ungated lint job (`hcl format --check` + `hcl validate`, no secret access, runs immediately on
  every PR) and a separately approval-gated validate job (`terragrunt validate --all`, the only
  step needing `SOPS_AGE_KEY`) — smaller gated surface and faster feedback on plain syntax errors
  than keeping the whole sequence behind approval.
- Whether `infra/modules/karpenter/terraform.tf`'s native, zero-config Renovate coverage could
  leak into production once production adopts the `karpenter`/`argocd-gitops` stacks: yes, this was
  a real dormant gap — resolved by explicitly scoping the `terraform` manager's file match to
  staging paths for this file too, rather than relying on Renovate's unscoped `**/*.tf` default
  (see Key Technical Decisions, Coverage Matrix).
- Whether the required-reviewer GitHub Environment gate is in scope for a v1 plan whose origin
  brainstorm only asked for a validate-and-report CI signal (R8/R9): yes, treated as a necessary
  scope addition surfaced by deepening's security review, and called out explicitly as such in Key
  Technical Decisions rather than left implicit.

### Deferred to Implementation

- [Needs research] Whether extending the `terraform` manager's `managerFilePatterns` to include
  staging's `terragrunt.hcl` files correctly extracts the `generate "providers"` heredoc's version
  constraints, evaluated **per stack** given the heterogeneous 1-4-provider block sizes — resolve
  by inspecting what Renovate actually proposes per stack (via the pre-merge onboarding PR if still
  open, or the Dependency Dashboard's rerun checkbox afterward) before writing final config, and
  exclude any stack moved to the `customManagers` fallback from the extended `terraform` manager's
  glob to avoid double-detection.
- [Technical] Exact `customManagers` `matchStrings` regex text for each of the three `env.hcl`
  patterns (module git-ref, `helm_charts` map entries, standalone chart-version inputs) —
  straightforward to write once implementation starts against the real file content captured
  above.
- [Technical] Exact GitHub Actions workflow YAML (trigger paths, job/step split, secret name, the
  GitHub Environment's required-reviewer configuration and reviewer list, whether "Prevent
  self-review" is enabled) — structure only; content is implementation, not planning.
- [Needs research] Whether `terragrunt validate --all` from the staging environment root correctly
  skips stacks unaffected by a given PR's diff, or whether the workflow should scope to only
  changed stacks for speed — a minor optimization question, not a correctness blocker either way
  since validating all six staging stacks is cheap and safe.
- [Needs research] Whether the external Terraform modules consuming secret-derived variables
  (`hcloud_token`, `cloudflare_api_token`, `gitops_repo_ssh_private_key`, SeaweedFS/S3 credentials)
  mark them `sensitive = true` upstream — if not, a `terragrunt validate` failure could print raw
  values in Terraform's own diagnostic output regardless of the workflow's own log hygiene.

---

## Implementation Units

- [ ] U1. **Install Renovate GitHub App and baseline scoped config**

**Goal:** Get the hosted Renovate GitHub App running against this repo with a config file that
already restricts scope to staging paths and disables auto-merge everywhere, before adding any
manager-specific coverage.

**Requirements:** R1, R2, R4, R7

**Dependencies:** None

**Files:**
- Create: `.github/renovate.json` (or `renovate.json` at repo root, per Renovate App convention)

**Approach:**
- Install the Renovate GitHub App on this repository (`bbayrakt/terragrunt-hcloud-kubernetes`) via
  GitHub's app-installation flow, granting it access to this repo only.
- Add a baseline config extending a sane default preset, with `enabledManagers` or per-manager
  `managerFilePatterns` scoping every manager to staging/ArgoCD paths, and a global
  `automerge: false`.
- Renovate only opens a one-time onboarding PR before a repository config file exists; once this
  baseline `renovate.json` is merged, there is no repeat onboarding PR. Edit U2/U3's
  `customManagers`/`managerFilePatterns` additions directly into this same pre-merge onboarding
  branch where practical, so the first merged config already reflects them; for any iterative
  per-stack verification needed after merge (U3's dry-run checks), use the Dependency Dashboard
  issue's manual rerun checkbox rather than expecting a fresh onboarding PR each time.

**Test scenarios:**
- Happy path: after installation, Renovate opens an onboarding PR proposing a `renovate.json`;
  merging it enables scheduled runs.
- Edge case: onboarding PR's dependency dashboard issue lists zero or partial dependencies from
  `infra/environments/production/**` — confirms path scoping is working before any manager-level
  config is layered on.
- Integration: after this one-time onboarding PR is merged, U3's per-stack verification uses the
  Dependency Dashboard's rerun checkbox rather than a fresh onboarding PR, since Renovate does not
  reopen onboarding once a config file exists.

**Verification:**
- Renovate app shows as installed and active in the repo's GitHub App settings.
- The onboarding PR's file scope excludes every `infra/environments/production/**` path.

---

- [ ] U2. **Custom regex coverage for `env.hcl` version strings**

**Goal:** Detect and propose bumps for the three version-pin shapes living in
`staging/env.hcl` that no built-in Renovate manager matches by default.

**Requirements:** R3

**Dependencies:** U1

**Files:**
- Modify: `.github/renovate.json`

**Approach:**
- Add a `customManagers` (regex) entry scoped to `infra/environments/staging/env.hcl` matching the
  `kubernetes_module_version` local, using the `github-tags` datasource against
  `hcloud-k8s/terraform-hcloud-kubernetes`.
- Add a second `customManagers` entry (or one entry with multiple `matchStrings`) for
  `helm_charts.external-dns.version`, `helm_charts.argocd.version`, and `external_dns_version`,
  using the `helm` datasource with each entry's `depName`/`registryUrl` derived from the adjacent
  `chart`/`repository` fields already present in the `helm_charts` map.
- `karpenter_chart_version` needs a **separate, OCI-aware entry, not the plain `helm` datasource**:
  it is not part of the `helm_charts` map (no adjacent `chart`/`repository` fields to derive from),
  and `infra/modules/karpenter/variables.tf` defaults `helm_repository` to
  `oci://ghcr.io/paperclipinc/charts` and `helm_chart` to `karpenter-provider-hetzner`, neither
  overridden in staging. Renovate's `helm` datasource performs an HTTP GET against
  `<registryUrl>/index.yaml` and does not understand `oci://` URLs when driven from a
  `customManagers` entry (unlike the native `helm` *manager*, which auto-detects OCI charts in
  `Chart.yaml`) — pointing it at this OCI source would silently fail to produce PRs. Use a
  `docker`-datasource (or equivalent OCI-aware) entry instead, with the package name
  (`ghcr.io/paperclipinc/charts/karpenter-provider-hetzner`) hardcoded in the regex config rather
  than derived, since the repository/chart name only exists as a module default.

**Technical design:** *(directional guidance only, not implementation specification)*
```
customManagers:
  - managerFilePatterns: [infra/environments/staging/env.hcl]
    matchStrings: [kubernetes_module_version\s*=\s*"(?<currentValue>[^"]+)"]
    datasourceTemplate: github-tags
    depNameTemplate: hcloud-k8s/terraform-hcloud-kubernetes
  - managerFilePatterns: [infra/environments/staging/env.hcl]
    matchStrings: [version\s*=\s*"(?<currentValue>[^"]+)"  # per helm_charts entry / standalone input]
    datasourceTemplate: helm
    depNameTemplate: <chart>
    registryUrlTemplate: <repository>
  - managerFilePatterns: [infra/environments/staging/env.hcl]
    matchStrings: [karpenter_chart_version\s*=\s*"(?<currentValue>[^"]+)"]
    datasourceTemplate: docker  # OCI-aware; helm datasource does not handle oci:// via customManagers
    depNameTemplate: ghcr.io/paperclipinc/charts/karpenter-provider-hetzner
```

**Test scenarios:**
- Happy path: upstream `hcloud-k8s/terraform-hcloud-kubernetes` publishes a new tag → Renovate
  proposes a PR updating only `kubernetes_module_version` in `staging/env.hcl`.
- Happy path: upstream `argo-cd` Helm chart publishes a new version → Renovate proposes a PR
  updating `helm_charts.argocd.version` only.
- Happy path: the OCI-hosted `karpenter-provider-hetzner` chart publishes a new version → the
  `docker`-datasource entry proposes a PR updating `karpenter_chart_version` — confirm this
  actually resolves against the real `ghcr.io/paperclipinc/charts` registry before trusting it,
  since the OCI-aware mechanism's success against this specific registry is unverified until a
  dry-run.
- Edge case: `external_dns_version` and `helm_charts.external-dns.version` currently hold the same
  value (`1.20.0`) but are two separate strings in the file — verify both update together in one
  PR (same category grouping) rather than drifting apart.
- Integration: confirm the regex does not also match `infra/environments/production/env.hcl`
  (different file path, should be a no-op given the `managerFilePatterns` scoping).

**Verification:**
- A manual Renovate dry-run (or its dependency dashboard) lists all five `env.hcl` version strings
  (including `karpenter_chart_version` via the OCI-aware entry) as tracked dependencies with
  correct current/available versions.

---

- [ ] U3. **Terraform provider version constraint coverage (`generate` blocks)**

**Goal:** Detect and propose bumps for the provider version constraints embedded in each staging
stack's `generate "providers"` heredoc.

**Requirements:** R3

**Dependencies:** U1

**Files:**
- Modify: `.github/renovate.json`

**Approach:**
- First attempt: extend the built-in `terraform` manager's `managerFilePatterns` to include
  `infra/environments/staging/{crds,gateway-api,helm-charts,karpenter,argocd-gitops}/terragrunt.hcl`.
- Run a dry-run/onboarding pass and inspect what dependencies it actually extracts **per stack**
  (per the Open Questions item on this) — given the heterogeneous heredoc sizes (1 provider in
  `gateway-api`/`argocd-gitops`, 2 in `crds`/`helm-charts`, 4 in `karpenter`), expect partial
  success rather than a uniform result across all five.
- For any stack where extraction is incomplete or misses entries, add a per-stack `customManagers`
  regex entry keyed to the `terraform-provider` datasource instead, one per provider line
  (`hashicorp/kubernetes`, `hashicorp/helm`, `hetznercloud/hcloud`, `siderolabs/talos`,
  `argoproj-labs/argocd`) — and **exclude that same stack's file** from the extended `terraform`
  manager's glob at the same time, so the two mechanisms never both match the same heredoc line.
- `karpenter/terraform.tf`'s `required_version` needs one line of scoping config, not zero: add
  `infra/modules/karpenter/terraform.tf` to the `terraform` manager's `managerFilePatterns`
  explicitly rather than leaving it on Renovate's unscoped `**/*.tf` default — the default would
  otherwise start matching this same file against production once production adopts the
  `karpenter` stack (see Key Technical Decisions).

**Execution note:** Verify against the real dry-run output before finalizing config; do not assume
either mechanism works without observing it (see Open Questions — deferred to implementation).

**Test scenarios:**
- Happy path: `hashicorp/helm` provider publishes a new `3.x` version within the `~> 3.1`/`~>
  3.2.0` range constraint on the relevant stacks → Renovate proposes a PR bumping only the range
  bound per its configured `rangeStrategy`.
- Edge case: `argoproj-labs/argocd`'s pin (`7.15.3`) has no range operator (exact pin) — confirm
  Renovate proposes an exact-version bump PR rather than silently ignoring it as already-pinned.
- Edge case: `siderolabs/talos` (`0.11.0`, no range operator) behaves the same way as the argocd
  provider case above.
- Integration: confirm a bump to one stack's `generate` block does not also alter another stack's
  independent `generate` block for the same provider (e.g. `hashicorp/kubernetes` appears in four
  different stacks' heredocs) — each stack's PR/diff should be scoped to that stack's file only.

**Verification:**
- Every provider version constraint enumerated in the origin doc's repo research (across all five
  stacks with `generate "providers"` blocks) appears as a tracked dependency in Renovate's
  dependency dashboard, correctly attributed to its own stack file.

---

- [ ] U4. **ArgoCD-managed Chart.yaml coverage, grouping, scheduling, and merge policy**

**Goal:** Cover `platform/*/Chart.yaml` (native, no custom config) and finalize the
category-grouping, weekly-schedule, and no-auto-merge policy across every manager configured in
U1-U3.

**Requirements:** R3, R5, R6, R7

**Dependencies:** U1, U2, U3

**Files:**
- Modify: `.github/renovate.json`

**Approach:**
- Confirm the `helm` manager's default `fileMatch` already covers `platform/**/Chart.yaml` (it
  matches `Chart.yaml` by convention); explicitly add `apps/**/Chart.yaml` to the same scope so a
  future app picked up automatically once one exists.
- Add `packageRules` grouping into four `groupName`s: Terraform providers, the module git-ref,
  Terraform-managed Helm charts, and ArgoCD-managed Helm charts — one rule per category matching
  the relevant `datasource`/`depType`/`fileMatch` combination from U1-U3.
- Set `schedule` to a weekly cadence at the top level (or per group, if categories should run on
  different days — default to a single weekly window unless a reason to stagger emerges).
- Set `automerge: false` globally (already set in U1; re-confirm no per-group override
  contradicts it).

**Test scenarios:**
- Happy path: a week with bumps available in two categories (e.g. one Terraform provider, one
  ArgoCD chart) produces exactly two grouped PRs, not four+ individual ones.
- Edge case: a week with zero available bumps produces zero PRs (no noise).
- Edge case: a bump to `sealed-secrets` and a bump to `vpa` in the same run land in the same
  "ArgoCD-managed Helm charts" grouped PR, not two separate PRs.
- Integration: no PR from any category auto-merges even after its CI check (from U6) passes.

**Verification:**
- A full week's dependency dashboard / PR history shows PRs arriving on the intended weekly
  cadence, grouped by the four categories, none auto-merged.

---

- [ ] U5. **Provision the CI-only SOPS age keypair**

**Goal:** Create a dedicated age keypair for CI decryption, register it as a second `.sops.yaml`
recipient, and re-encrypt `infra/secrets.yaml` for both recipients.

**Requirements:** R9

**Dependencies:** None

**Files:**
- Modify: `.sops.yaml`
- Modify: `infra/secrets.yaml` (re-encrypted ciphertext only, via `sops updatekeys`)

**Approach:**
- Generate a new age keypair dedicated to CI use (kept out of git, same discipline as the existing
  `infra/keys.txt`).
- Update `.sops.yaml`'s single `creation_rules` entry (`path_regex: secrets\.yaml$`) to list both
  the existing recipient and the new CI recipient as a comma-separated `age:` value.
- Run `sops updatekeys` against `infra/secrets.yaml` to re-encrypt the data key for both
  recipients without altering the encrypted content itself.
- Store the CI keypair's private key as a GitHub Actions repository secret (name to be finalized
  in U6, e.g. `SOPS_AGE_KEY`).
- Document the rotation runbook as a standing operational step, not a one-time note: whenever
  `.sops.yaml`'s recipient list changes for any reason (rotating the CI key, rotating the
  operator's key, or a future per-environment secrets split), re-run `sops updatekeys` against
  `infra/secrets.yaml` for the *current full recipient set* and re-verify decrypt with every
  remaining key — recipient metadata is baked into the encrypted file at `updatekeys` time, not
  re-derived from `.sops.yaml` on every edit, so a skipped `updatekeys` run fails silently (the
  file keeps decrypting fine for whoever was already embedded, with no error signaling that a
  newly-declared recipient is actually locked out).

**Test scenarios:**
- Happy path: after `sops updatekeys`, both the operator's existing local `infra/keys.txt` and the
  new CI private key can independently decrypt `infra/secrets.yaml`.
- Edge case: the operator's existing local decrypt workflow (`SOPS_AGE_KEY_FILE=infra/keys.txt`)
  continues to work unchanged after the recipient list is updated — this must not regress.
- Edge case: simulate the rotation runbook once (e.g. by re-running `updatekeys` a second time
  with the same two recipients) to confirm the documented procedure is actually idempotent and
  produces no drift before relying on it for a future real rotation.
- Test expectation: no automated test possible for the secret material itself; verification is
  manual (attempt a decrypt with each key locally before trusting CI).

**Verification:**
- `sops -d infra/secrets.yaml` succeeds locally with the operator's existing key (unchanged
  behavior).
- A local, throwaway decrypt attempt using the new CI private key also succeeds, confirming it was
  registered correctly before it's trusted as a GitHub secret.

---

- [ ] U6. **GitHub Actions CI validation workflow**

**Goal:** Add a PR-triggered workflow that runs the existing manual validation sequence against
staging, using the CI-only SOPS key from U5, gated so PR-supplied HCL cannot exercise decrypt
access before a human explicitly approves the run.

**Requirements:** R8, R9, R10

**Dependencies:** U1, U5

**Files:**
- Create: `.github/workflows/terragrunt-validate.yml`
- Modify: `.github/renovate.json` (confirm/extend `github-actions` manager scope to
  `.github/workflows/**` — likely already covered by default, verify no restriction excludes it)

**Approach:**
- Trigger on `pull_request` (not `pull_request_target`) for paths under
  `infra/environments/staging/**` and `infra/modules/**`.
- Split into two jobs rather than one, now that planning resolved whether `hcl format`/`hcl
  validate` need decryption (see Open Questions — they don't): an ungated **lint** job runs
  `terragrunt hcl format --check` and `terragrunt hcl validate` from repo root on every PR
  immediately, with no secret access; a separate, approval-gated **validate** job runs
  `terragrunt init -reconfigure && terragrunt validate --all` from `infra/environments/staging/`,
  the only step that needs `SOPS_AGE_KEY`.
- Route the **validate** job through a GitHub Environment (e.g. `ci-secrets-staging`) configured
  with required reviewers, so the secret is only exposed to a run after a human explicitly
  approves it for that commit — this is the control that closes the code-execution-before-review
  gap identified during deepening (see Key Technical Decisions): Terragrunt evaluates
  `generate`/`before_hook` blocks as ordinary config parsing, so a branch-pushed PR could otherwise
  exfiltrate decrypted secret material the instant the job runs, before any diff review. Name the
  required-reviewer group explicitly and enable the environment's "Prevent self-review" setting so
  a PR author who is also a reviewer cannot approve their own run; the approving reviewer is
  expected to have inspected the diff for `generate`/`before_hook`/workflow-file changes, not just
  clicked approve on a routine-looking bump PR.
- **`SOPS_AGE_KEY` must be created as a GitHub Actions *environment secret* bound to
  `ci-secrets-staging`, not a repository secret.** A repository secret is readable by any job in
  any workflow regardless of whether it declares the gated environment — a PR that adds a new job
  or step reading `secrets.SOPS_AGE_KEY` without referencing the environment would retrieve it with
  no approval at all, silently reopening the exact gap the environment gate exists to close. No
  other job or workflow in the repo should declare the `ci-secrets-staging` environment or
  otherwise gain access to this secret.
- Add an explicit least-privilege `permissions:` block at workflow or job level (e.g. `contents:
  read`, nothing else) rather than relying on the repository's default `GITHUB_TOKEN` scope.
- Never interpolate untrusted event context (PR title, head ref, commit message, labels) directly
  into a shell `run:` step in either job — a well-known GitHub Actions script-injection vector that
  would grant the same decrypt-capable code execution the environment gate was built to prevent,
  via a different mechanism. Pass any such values through `env:` variables instead of template
  interpolation if they're ever needed.
- Steps (validate job): checkout, install `sops`/`age`/`terragrunt`/`terraform` tooling, export
  `SOPS_AGE_KEY_FILE` pointed at a file written from the `SOPS_AGE_KEY` secret (or export
  `SOPS_AGE_KEY` directly per `sops`'s supported env var, whichever avoids writing plaintext to
  disk), then run `terragrunt init -reconfigure && terragrunt validate --all`.
- Avoid the `set -e` + `X=$(cmd)` pitfall documented in
  `docs/solutions/architecture-patterns/self-hosted-gitops-monorepo-migration-terragrunt-sops-state-preservation-2026-08-01.md`
  — any step capturing command output for a conditional check uses an explicit `if`, not a bare
  assignment relying on `set -e`.
- Never echo or upload decrypted secret material as a log line or artifact; be aware that a
  `terragrunt validate` failure can surface raw values in Terraform's own diagnostic output if an
  upstream module doesn't mark a secret-derived variable `sensitive` (see Open Questions) — this
  is a gap in the module, not something the workflow's own log discipline can fully close.

**Execution note:** Treat this as infrastructure/config, not application code — no unit test
framework applies; correctness is verified by observing actual workflow runs against real PRs
(including U1's onboarding PR and a deliberately-broken test PR), and by confirming the
required-reviewer gate actually blocks the validate job from starting without approval while the
lint job runs unconditionally.

**Test scenarios:**
- Happy path: a PR with valid staging HCL changes shows the lint job passing immediately, and the
  validate job passing once a named reviewer approves it.
- Error path: a PR with a deliberately invalid `terragrunt.hcl` (e.g. malformed HCL) shows the
  lint job failing at `terragrunt hcl validate`, without ever needing the validate job or secret
  access.
- Error path: temporarily using a wrong/empty SOPS key value shows the validate job failing at
  decrypt time with a clear error, not a silent pass.
- Security: a PR that adds or modifies a `generate`/`before_hook` block under the trigger paths
  does **not** get decrypt-capable job execution until a reviewer approves the run — the approval
  gate must block the validate job from starting at all, not just from succeeding.
- Security: confirm `SOPS_AGE_KEY` is genuinely inaccessible to a job/step that does not declare
  the `ci-secrets-staging` environment (e.g. attempt to read it from an ordinary, ungated job and
  confirm the read fails) before trusting the environment-secret scoping.
- Integration: a PR opened by Renovate (from U1-U4) is picked up by this workflow like any other
  PR, and still requires the same reviewer approval before its validate job runs, since Renovate
  commits branches directly to this repo rather than a fork.
- Test expectation for the `github-actions` manager scope change: none -- pure config
  confirmation, no behavior change beyond what Renovate already does by default for
  `.github/workflows/**`.

**Verification:**
- Both jobs appear as required status checks on real PRs touching staging (blocking the merge
  button, consistent with R7's manual-merge requirement — a required check still requires an
  explicit human merge action, it does not merge anything itself); the validate job visibly waits
  for reviewer approval before starting.
- A known-good PR passes both jobs after approval; a deliberately broken PR fails at the expected
  step without ever reaching the gated job if the failure is lint-level.
- The workflow's effective token permissions are confirmed to be read-only/minimal, not the
  unscoped default.
- `SOPS_AGE_KEY` is confirmed to be an environment secret, not a repository secret, and no other
  job in the repo can read it.

---

- [ ] U7. **Documentation updates**

**Goal:** Make the new bot and CI workflow discoverable and explain the residual secret-exposure
risk in the repo's own documentation, matching its existing habit of documenting workflow and
security decisions.

**Requirements:** R5, R6, R7, R9 (residual risk transparency)

**Dependencies:** U1-U6 (describes the finished state)

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`

**Approach:**
- Note in README.md/AGENTS.md that staging's dependency versions are now Renovate-managed
  (weekly, grouped by category, no auto-merge) and link to
  `docs/brainstorms/renovate-dependency-updates-staging-requirements.md` for the rationale.
- Document the CI-only SOPS age key's existence and scope precisely: it can decrypt the full
  shared `infra/secrets.yaml`, including the Hetzner Cloud API token, Cloudflare API token, the
  GitOps repository's SSH deploy key, SeaweedFS/S3 credentials, and the platform-tier SOPS age
  key (which itself decrypts `platform/` KSOPS secrets) — not just an abstract "production's
  secrets." Name the concrete blast radius so a future reader doesn't have to re-derive it from
  `.sops.yaml`.
- Document the CI job's required-reviewer approval gate (U6) as the control that keeps this
  exposure bounded to "after a human approves this specific run," not "automatic on every PR" —
  including that the key is an environment secret (not a repository secret), that self-review is
  disabled, and that the gate's availability depends on this repository remaining public (GitHub's
  required-reviewer environment protection is public-repo-only on Free/Pro/Team plans and is
  silently ignored if the repo is ever made private).
- Document the `.sops.yaml` recipient-rotation runbook from U5 as a standing procedure (not a
  point-in-time note): any future recipient change requires re-running `sops updatekeys` for the
  full current recipient set and re-verifying decrypt with every remaining key.
- Document the ArgoCD-managed-chart immediate-deploy asymmetry from Key Technical Decisions:
  `platform/`/`apps/` Chart.yaml bump PRs deploy on merge via ArgoCD's `automated { prune: true }`
  sync policy, with no separate `terragrunt apply` gate, unlike the other three bump categories —
  and that this is currently a documentation-level scrutiny norm, not a separate technical gate,
  given the single-operator review model already applies R7's manual-merge requirement uniformly
  to every category.
- Document that `infra/modules/karpenter/terraform.tf`'s Renovate coverage is deliberately scoped
  to staging paths rather than left on Renovate's default `**/*.tf` match, specifically so it
  doesn't silently start touching production once production adopts the `karpenter` stack.
- Leave the existing "Required validation workflow" section unchanged in meaning — the CI workflow
  automates the same steps, it doesn't replace the operator's ability to run them locally.

**Test scenarios:**
- Test expectation: none -- documentation-only change, no behavior to verify beyond accuracy
  against the finished U1-U6 state.

**Verification:**
- A new reader of README.md/AGENTS.md can tell, without reading `.github/renovate.json` or
  `.sops.yaml` directly, what's automated, what isn't, and what the CI key can access.

---

## System-Wide Impact

- **Trust boundary:** the operative trust boundary for U6's CI job is "anyone who can push a
  branch that opens a PR against trigger paths" (Renovate's own branches, or any future
  collaborator), not "anyone who can merge." Terragrunt evaluates `generate`/`before_hook` blocks
  as ordinary config parsing at `validate` time, so decrypt-capable code execution is reachable
  before any human review unless gated — this is why U6 routes the secret-bearing job through a
  required-reviewer GitHub Environment rather than relying on no-auto-merge alone.
- **Interaction graph:** Renovate-opened PRs now flow through the new CI workflow (U6) as their
  only automated check; no other CI exists to interact with. `argocd-gitops`'s `ApplicationSet`
  reconciliation loop is the downstream consumer of any merged `platform/*/Chart.yaml` bump — and
  unlike the other three bump categories, that loop's `automated { prune: true }` sync policy means
  merge itself triggers a live deploy, with no separate `terragrunt apply` gate. Its release-naming
  convention is also why bumps still warrant a manual `helm template` spot-check post-merge (see
  Scope Boundaries).
- **Error propagation:** Both CI jobs are configured as required status checks that block the
  merge button until they pass — this does not contradict the no-auto-merge decision (R7): a
  required check still requires an explicit human merge action, it just cannot be a mistaken
  click on a failing PR. The required-reviewer gate (U6) adds a second, earlier propagation point
  for the validate job specifically: it simply does not start without approval, rather than
  starting and then reporting failure.
- **State lifecycle risks:** The `sops updatekeys` step (U5) rewrites `infra/secrets.yaml`'s
  ciphertext (re-encrypting the data key for two recipients) without changing its plaintext
  contents — a one-time, reversible operation, but any error mid-operation should be caught before
  committing (verify decrypt with both keys locally first, per U5's verification). This is not
  purely one-time, though: any future recipient-list change repeats the same risk and requires the
  same re-verification (U5's rotation runbook).
- **API surface parity:** N/A — no application API surface exists in this repo.
- **Integration coverage:** U6's validate job reuses the exact same `sops_decrypt_file` mechanism
  that `env.hcl` already calls locally — no divergent decrypt path is introduced, so CI and local
  developer behavior stay consistent. Only the validate job needs this mechanism; the lint job
  (`hcl format`/`hcl validate`) is pure syntax/schema checking and needs no decryption (resolved
  during deepening, see Open Questions), which is why only the validate job sits behind the
  approval gate.
- **Unchanged invariants:** The operator's existing local workflow
  (`SOPS_AGE_KEY_FILE=infra/keys.txt`, manual `terragrunt hcl format/validate` + per-stack
  `terragrunt validate`) is completely unchanged by this plan — CI runs the same steps in parallel
  using a separate, dedicated key, not a replacement for the local flow.
- **External dependency on repo visibility:** the required-reviewer environment gate (U6), the
  plan's primary control for the code-execution-before-review risk, depends on this repository
  remaining public — GitHub's environment protection rules with required reviewers are available
  on Free/Pro/Team plans for public repositories only, and are silently ignored if the repo is
  ever converted to private. This dependency sits outside this plan's control and should be
  re-verified if repo visibility ever changes (see Risks & Dependencies).

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| A PR-supplied `generate`/`before_hook` block can execute arbitrary code with decrypt access during `terragrunt validate`, before human review — no-auto-merge and avoiding `pull_request_target` don't constrain what runs *during* the job itself | U6 routes the secret-bearing validate job through a GitHub Environment requiring reviewer approval before it starts for a given commit, independent of merge policy (added during deepening's security review) |
| A repository-scoped (rather than environment-scoped) `SOPS_AGE_KEY` secret would let any job/step read it regardless of whether it declares the gated environment, silently reopening the code-execution-before-review gap the environment gate exists to close | U5/U6 require `SOPS_AGE_KEY` to be created as a GitHub Actions *environment secret* bound to `ci-secrets-staging`, not a repository secret, and verify no other job can read it |
| A PR author who is also a listed required reviewer could approve their own run, or a reviewer could rubber-stamp approval without inspecting the diff for `generate`/`before_hook`/workflow-file changes, making the approval gate technically present but practically ineffective | U6 names the required-reviewer group explicitly, enables the environment's "Prevent self-review" setting, and documents that approval is conditioned on diff inspection, not a reflexive click |
| The required-reviewer environment gate depends on this repository remaining public — GitHub's required-reviewer environment protection is public-repo-only on Free/Pro/Team plans and is silently ignored if the repo is ever made private, with no error signal when that happens | Documented explicitly as an external dependency in System-Wide Impact and README/AGENTS.md (U7); re-verify the gate is still active if repo visibility ever changes |
| Untrusted GitHub Actions event context (PR title, branch name, commit message) interpolated directly into a shell `run:` step is a well-known script-injection vector that could grant the same decrypt-capable execution the environment gate was built to prevent, via a different mechanism | U6 explicitly avoids interpolating event context into `run:` steps, using `env:` variables instead if such values are ever needed |
| CI-only age key's blast radius extends beyond "production's secrets" to the full shared secret set — Hetzner Cloud API token (account control), Cloudflare API token, the GitOps repo's SSH deploy key (write access into the GitOps repo), SeaweedFS/S3 credentials, and the platform-tier SOPS age key (itself decrypts `platform/` KSOPS secrets) — since there's one file/recipient rule for both environments | Named explicitly in README/AGENTS.md (U7), not left abstract; mint a dedicated, independently-revocable CI key (U5) rather than reusing the operator's; the required-reviewer gate above bounds *when* that access is reachable; splitting secrets per environment is out of scope |
| A `terragrunt validate` failure could print raw secret values in Terraform's own diagnostic output if an upstream module doesn't mark a secret-derived variable `sensitive` — the workflow's own "never echo" discipline can't prevent this | Flagged as a [Needs research] Open Question to check upstream module `sensitive` marking before trusting CI logs as safe by default |
| Renovate's built-in `terraform`/`terragrunt` managers may not correctly extract provider constraints embedded in `terragrunt.hcl` generate-block heredocs, and a per-stack fallback could double-detect the same line if not mutually exclusive with the native manager's glob | U3 plans a per-stack native-first attempt with a `customManagers` regex fallback, explicitly excluding any stack that falls back from the native manager's file scope, verified via dry-run before finalizing |
| `infra/modules/karpenter/terraform.tf`'s otherwise-native Renovate coverage relies on an unscoped default glob that would silently start touching production once production adopts the `karpenter` stack | U3/Key Technical Decisions explicitly scope the `terraform` manager's file match to staging paths for this file too, instead of leaving it on the unscoped default |
| ArgoCD's `automated { prune: true }` sync policy means merging a `platform`/`apps` Chart.yaml bump deploys immediately with no separate `terragrunt apply` gate, unlike the other three bump categories — the "native, zero-config" framing of this category could be mistaken for "lower risk", and this category currently has a documentation-level scrutiny norm rather than a technical control analogous to U6's approval gate | Called out explicitly in Key Technical Decisions and README/AGENTS.md (U7): reviewers should treat this category with equal or greater scrutiny, not less; accepted as documentation-only for a single-operator repo rather than adding a second technical gate on top of R7's existing manual-merge requirement |
| `.sops.yaml` recipient-list changes require re-running `sops updatekeys`, and drift is silent — a skipped run leaves a newly-declared recipient locked out with no error signal | U5/U7 document a standing rotation runbook (not a one-time step) and a re-verification habit whenever the recipient list changes |
| `terragrunt validate` is static-only and cannot catch chart-render or ArgoCD-provider regressions (per prior incidents in `docs/solutions/`) | Documented explicitly in Scope Boundaries and README/AGENTS.md (U7) so the CI green check isn't over-trusted; manual `helm template` spot-check recommended for chart bumps |
| A CI workflow step could accidentally log or leak decrypted secret material | U6 explicitly avoids echoing decrypted values, avoids the `set -e` + assignment pitfall from institutional learnings, and scopes `GITHUB_TOKEN` permissions to read-only |
| Renovate PRs pile up if grouping/scheduling config is misconfigured, defeating the "few PRs per run" goal (R5) | U4's test scenarios explicitly check grouping behavior before considering the work complete |
| Renovate could be installed and start opening weekly bump PRs before U6's CI workflow exists, since no formal unit dependency enforces the order, undermining this plan's own rationale that CI gives bump PRs a real signal before review | Treat U6 as a practical prerequisite for enabling Renovate's scheduled runs, even though the units have no formal cross-dependency (see Key Technical Decisions) |
| Keeping staging on a weekly Renovate cadence while production stays frozen until its GitOps migration lands mechanically widens the drift this plan is framed as addressing, making the eventual production catch-up a larger multi-version jump | Accepted tradeoff: staging-only v1 scope was a deliberate origin-brainstorm decision; this plan doesn't reduce cross-environment drift, it only automates staging's side, and that is an argument for prioritizing the production GitOps migration rather than a defect in this plan |
| Granting the hosted Renovate GitHub App repo access is a standing third-party trust relationship | Already an explicit, informed user decision from the origin brainstorm (chosen over self-hosting) |

---

## Documentation / Operational Notes

- Update README.md and AGENTS.md per U7 to describe the new bot and CI workflow, and the CI key's
  scope.
- Once this lands, capture a `/ce-compound` entry noting the Renovate + CI-validate setup as new
  institutional territory for this repo (per `ce-learnings-researcher`'s finding that no such
  learning exists yet).
- No monitoring/alerting changes — PR arrival on GitHub is the only signal; no additional
  dashboards proposed.

---

## Sources & References

- **Origin document:** [docs/brainstorms/renovate-dependency-updates-staging-requirements.md](docs/brainstorms/renovate-dependency-updates-staging-requirements.md)
- Related docs: `docs/solutions/architecture-patterns/self-hosted-gitops-monorepo-migration-terragrunt-sops-state-preservation-2026-08-01.md`,
  `docs/solutions/architecture-patterns/argocd-two-tier-rbac-boundary-and-arc-onboarding-2026-08-02.md`,
  `docs/solutions/integration-issues/terragrunt-apply-all-destroy-all-multi-stack-2026-08-02.md`,
  `docs/solutions/integration-issues/argocd-provider-config-path-tls-cert-verification-failure-2026-07-31.md`
- Related docs: `docs/brainstorms/argocd-gitops-migration-requirements.md` (production migration
  this work is deliberately waiting on)
- External docs: <https://docs.renovatebot.com/modules/manager/terragrunt/>,
  <https://docs.renovatebot.com/modules/manager/terraform/>,
  <https://docs.renovatebot.com/modules/manager/regex/>
