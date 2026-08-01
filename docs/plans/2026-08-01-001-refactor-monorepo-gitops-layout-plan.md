---
title: Monorepo Layout for Terraform/Terragrunt + Self-Hosted ArgoCD GitOps Content
type: refactor
status: completed
date: 2026-08-01
deepened: 2026-08-01
origin: docs/brainstorms/argocd-gitops-migration-requirements.md
---

# Monorepo Layout for Terraform/Terragrunt + Self-Hosted ArgoCD GitOps Content

## Overview

This repository stops assuming a separate, dedicated GitOps repository for ArgoCD-managed app
manifests and becomes that repository itself. All existing Terraform/Terragrunt content moves
into a new top-level `infra/` subfolder; `apps/` and `platform/` become top-level directories at
the true repo root, created here as empty skeleton `README.md` placeholders — real application
content lands in a follow-up increment (see Scope Boundaries); the
`argocd-gitops` Terraform module's ApplicationSet directory-generator paths become configurable
(`gitops_apps_path` / `gitops_platform_path`) instead of hardcoded, and its `gitops_repo_url`
variable is reframed to treat self-referencing monorepo and dedicated split-repo as equally
supported topologies. Staging's live `argocd-gitops` stack is then repointed to self-reference
this repo.

---

## Problem Frame

The prior migration (`docs/plans/2026-07-30-001-feat-argocd-gitops-migration-plan.md`, merged)
built the two-tier ArgoCD `AppProject`/`ApplicationSet` architecture assuming a new, separate
GitOps repository would host `apps/`/`platform/` content — that repo was never created. The
operator has since decided this repo should serve that role instead (see
`docs/brainstorms/argocd-gitops-migration-requirements.md`'s 2026-08-01 amendment, R10–R20),
specifically to avoid the operational overhead of a second repo/credential for a single-operator
setup with no team-based access-control layer today. That amendment fully resolved the product
question (monorepo vs. split repo, what moves where, why); this plan resolves the remaining
technical "how" — the concrete file moves, path-reference repairs, module changes, and sequencing
needed to realize it safely, including verifying no remote-state drift and no regression of a
previously-documented ArgoCD-provider TLS issue.

---

## Requirements Trace

**GitOps repo identity & registration**
- R10. This repository is the GitOps content repository — no separate repo is created; `apps/`
  and `platform/` live as top-level directories at the true repo root.
- R11. This repo is registered with ArgoCD via `argocd_repository`; `gitops_repo_url` stays a
  plain configurable variable so a future reuser can point it at a split repo instead.

**File-layout relocation**
- R16. All existing Terraform/Terragrunt content moves into a new top-level `infra/` subfolder.
- R17. `apps/`, `platform/`, `docs/`, `.sops.yaml`, `README.md`, and `AGENTS.md` remain at the
  true repository root.
- R18. `.sops.yaml` stays at the true repository root (structural precondition for a future
  platform-tier SOPS rule to coexist with the existing `secrets.yaml` rule — no new rule is added
  in this plan, since no platform-tier content exists yet to govern).

**Module configurability**
- R19. `modules/argocd-gitops`'s hardcoded `apps/*` / `platform/*` generator paths become
  configurable via `gitops_apps_path` / `gitops_platform_path`, defaulting to `"apps"` /
  `"platform"`.
- R20. `gitops_repo_url`'s variable description and the module README are reworded to present
  self-referencing monorepo and dedicated split-repo as equally supported topologies.

**Origin flows:** F1 (add an `apps`-tier app) and F2 (add a `platform`-tier app) are unaffected in
substance by this plan — both still describe committing a new directory under the (now
true-repo-root) `apps/`/`platform/` trees. F3 (migrate the two runner charts) remains the
responsibility of the original, already-merged plan's still-open units (authoring real GitOps
content) and is explicitly out of scope here (see Scope Boundaries).

---

## Scope Boundaries

- Authoring the actual `apps/`/`platform/` GitOps content (Helm wrapper charts, `SealedSecret`
  manifests, the real per-app directories described in `docs/gitops-repo-scaffold.md`) is not
  done in this plan — it requires a live cluster, the Sealed Secrets controller, and `kubeseal`,
  none of which this plan touches. `apps/` and `platform/` are created here only as empty,
  git-trackable skeletons (a short `README.md` each) so the layout exists and is discoverable.
- Adding a `.sops.yaml` creation rule for `platform/**/*.sops.yaml` is not done in this plan —
  there is no platform-tier content yet to govern. **Correction from an earlier revision of this
  plan:** the platform-tier AGE key pair was previously claimed to already exist based on the
  `platform_sops_age_private_key` field being present in `secrets.yaml`; decrypting the actual
  value during execution showed it is still a literal placeholder (`AGE-SECRET-KEY-CHANGEME`), not
  a real generated key. Generating the real key pair remains deferred, alongside the `.sops.yaml`
  rule, until real platform-tier content exists to match against.
- The pre-existing dead references to `scripts/sync_kubernetes_wrapper.py` (`Makefile`'s
  `sync-k8s-wrapper` target) predate this plan and are unrelated to the move; left alone.
- Production has no `argocd-gitops` stack and no `gitops_*` inputs today (R15 of the origin doc),
  so U4/U5's ArgoCD-specific wiring and repoint do not touch it. Production's other four stacks
  (`kubernetes-cluster`, `gateway-api`, `crds`, `helm-charts`) **do** move in U2 along with
  staging's, and are explicitly in scope for U2's post-move state verification — "production is
  unaffected" applies only to the ArgoCD-gitops-specific units, not to the file move itself.
- Historical documents that reference pre-move paths in past-tense prose — the original
  `docs/plans/2026-07-30-001-feat-argocd-gitops-migration-plan.md` and the origin brainstorm —
  are intentionally left with their old paths unmodified; they are dated records of what was true
  when written, not live operational instructions. This is distinct from `docs/gitops-repo-scaffold.md`
  and the ArgoCD-provider-TLS institutional learning, both of which **are** updated in U3 because
  they are actively linked from this plan's own new content (U4's skeleton READMEs) or actively
  cited as required reading (this plan's own Institutional Learnings section) — leaving those two
  stale would introduce a fresh inconsistency, not just preserve an old one.
- `root.hcl`'s unused `environment` local (derived from `path_relative_to_include()`, consumed
  nowhere else in the codebase) is left as-is — out of scope, unrelated cleanup.

### Deferred to Follow-Up Work

- Authoring real `apps/`/`platform/` GitOps content per `docs/gitops-repo-scaffold.md`: separate,
  later increment (depends on live cluster + Sealed Secrets controller).
- Generating the real platform-tier AGE key pair (currently a placeholder,
  `AGE-SECRET-KEY-CHANGEME`) and adding the `.sops.yaml` rule for `platform/**/*.sops.yaml`:
  bundled with the content-authoring work above, since there's nothing to match or decrypt until
  real platform-tier files exist.
- Deciding where a future `scripts/sync_kubernetes_wrapper.py` would live (`infra/scripts/` vs.
  true-root `scripts/`): open, unrelated to this plan; the target script does not exist today.

---

## Context & Research

### Relevant Code and Patterns

- `root.hcl` (repo root): remote-state backend + `secrets.yaml` decryption, using
  `find_in_parent_folders()`/`path_relative_to_include()` — both resolve relative to the calling
  file's own location, never to a fixed repo-root path. This is what makes the whole Terraform
  tree relocatable as a unit without a state migration (see Key Technical Decisions).
- `environments/<env>/<module>/terragrunt.hcl`: every stack **except `kubernetes-cluster`**
  sources its module via `terraform { source = "../../../modules/<module>" }` (three `../` hops
  back to repo root). `kubernetes-cluster` is the one exception — both staging's and production's
  `terragrunt.hcl` source directly from a remote `git::https://github.com/hcloud-k8s/terraform-hcloud-kubernetes.git?ref=...`
  URL, not a local relative path, so it is entirely unaffected by the move either way. Every stack
  also depends on siblings via relative `config_path`s (e.g. `"../kubernetes-cluster"`). Both
  patterns are depth-agnostic as long as `environments/` and `modules/` move together, preserving
  their relative nesting.
- `modules/argocd-gitops/main.tf`: `directory { path = "apps/*" }` (line ~105) and
  `directory { path = "platform/*" }` (line ~176) inside the two `argocd_application_set`
  resources — the two hardcoded literals R19 replaces with variables.
- `modules/argocd-gitops/variables.tf`: existing `gitops_repo_url`/`gitops_repo_ssh_private_key`
  pattern (plain `string` variables sourced from `include.env.inputs.*` in
  `environments/staging/argocd-gitops/terragrunt.hcl`) is the pattern `gitops_apps_path`/
  `gitops_platform_path` should follow.
- `AGENTS.md` (root) and `README.md` (root, currently untracked in git per `git status`): both
  contain near-duplicate `cd environments/<env>/<module>` command blocks and
  `SOPS_AGE_KEY_FILE` exports that need the same `infra/` prefix treatment.
- `.gitignore` (root): every relevant pattern (`keys.txt`, `kubeconfig*`, `talosconfig*`,
  `**/.argocd-admin-password`, `**/.terraform.lock.hcl`, `**/.terragrunt-cache/`) is depth-agnostic
  (bare filename or `**/` prefixed) — confirmed to need **no changes** for the move.

### Institutional Learnings

- `docs/solutions/integration-issues/argocd-provider-config-path-tls-cert-verification-failure-2026-07-31.md`
  (severity: high): the `argoproj-labs/argocd` provider's `config_path` attribute fails TLS
  verification against this cluster's Talos-generated ECDSA CA; the working fix (explicit
  `kubernetes { host, cluster_ca_certificate, client_certificate, client_key }` block in
  `environments/staging/argocd-gitops/terragrunt.hcl`'s generated `providers.tf`) must be
  preserved verbatim through the move and re-verified with a real `terragrunt apply` — static
  `validate`/`hcl validate` will not catch a regression of this issue.

### External References

None consulted for this plan. This work is entirely repo-specific Terragrunt/Terraform/SOPS
mechanics with strong existing local patterns to follow (every path convention this plan touches
already has 3+ direct examples in the current tree). The one cross-cutting technical fact this
plan depends on — that SOPS resolves the nearest `.sops.yaml` by walking upward from the target
file, not from a fixed repo-relative path — was independently verified against `getsops.io`'s
official config-file reference during the originating brainstorm and is treated as settled here.

---

## Key Technical Decisions

- **`infra/` receives the move, not the GitOps content**: `environments/`, `modules/`, `root.hcl`,
  `Makefile`, `setup.sh`, `examples/`, `secrets.yaml`, `secrets.yaml.example`, `keys.txt` all move
  into `infra/`, unchanged relative to each other. `apps/`, `platform/`, `docs/`, `.sops.yaml`,
  `README.md`, `AGENTS.md` stay at the true root. Rationale: carried directly from the origin
  doc's R16/R17 and its rationale that this leaves the root free for `docs/gitops-repo-scaffold.md`'s
  already-written layout to apply unchanged. Two cheaper-looking alternatives — leaving Terraform
  in place and creating a second, minimal GitOps repo instead, or leaving Terraform in place and
  nesting GitOps content per-environment (e.g. `environments/<env>/gitops/`) — were both explicitly
  presented to and rejected by the operator during the originating brainstorm (see
  `docs/brainstorms/argocd-gitops-migration-requirements.md`'s 2026-08-01 amendment dialogue); this
  plan does not re-litigate that product decision, only executes it.
- **U2 (the move) and U5 (the ArgoCD self-reference repoint) are separate commits, not one
  atomic change**: U2 relocates every environment's Terraform content (including production's four
  independent stacks) in one filesystem operation, since it is one repo with one `infra/`
  destination — that part cannot be meaningfully split by environment. U5, by contrast, only
  touches `infra/secrets.yaml` and is sequenced strictly after U1/U4, as its own later, independent
  commit. A rollback of U5 (staging-only, ArgoCD-specific) never needs to touch or revert
  production's already-landed, unrelated stack relocation.
- **State keys are provably unaffected by the move**: `root.hcl`'s
  `key = "${path_relative_to_include()}/terraform.tfstate"` resolves relative to the *include
  block's own position*, not the filesystem root. Since `root.hcl` and `environments/` move
  together preserving their relative nesting, this expression evaluates to the identical string
  (e.g. `"environments/staging/kubernetes-cluster"`) before and after the move. No
  `terragrunt state mv` or backend re-init is required — but a live no-op `terragrunt plan` per
  stack immediately after the move is still required as an execution-time confirmation (this is
  an analytical guarantee about the expression, not a substitute for verifying the real S3-backed
  state matches).
- **`make -C infra <target> ...` over a root-level Makefile shim or requiring `cd infra` first**:
  since `Makefile`'s targets already use paths relative to its own invocation directory (e.g.
  `cd environments/$(ENV)/$(MODULE)`), moving the whole `Makefile` into `infra/` and invoking it
  with GNU Make's built-in `-C` flag (`make -C infra plan ENV=staging`) requires zero changes to
  the Makefile's own content — no shim script to maintain, no extra indirection layer. Documented
  as the primary invocation form in `README.md`.
- **`setup.sh`'s `.sops.yaml` reference becomes `$(git rev-parse --show-toplevel)/.sops.yaml`**,
  matching `AGENTS.md`'s existing portable convention for `keys.txt`, rather than a fragile
  `../.sops.yaml` relative literal that would break if `setup.sh` is ever invoked from a directory
  other than `infra/`.
- **No `.sops.yaml` or `.gitignore` content changes in this plan**: both files' existing rules are
  either unanchored regexes or depth-agnostic globs, confirmed to keep working unmodified once
  their governed files sit under `infra/`. A platform-tier `.sops.yaml` rule is added only once
  real platform-tier content exists (deferred, see Scope Boundaries).
- **`apps/`/`platform/` created as skeleton `README.md` stubs, not full scaffold content**: git
  does not track empty directories, so a minimal placeholder file (linking to
  `docs/gitops-repo-scaffold.md`) is the smallest change that makes the new top-level layout real
  and discoverable without inventing content that depends on a live cluster.
- **`.terragrunt-cache`/`.terraform.lock.hcl` disposability is a separate claim from state-key
  stability, not a consequence of it**: these caches key off the working directory's *absolute*
  path, which does change (`/repo/environments/...` → `/repo/infra/environments/...`), so old
  caches become orphaned garbage regardless of whether the S3 state key stays identical. They are
  safe to leave behind or delete because the `Makefile`'s own `clean` target already treats them
  as disposable — not because the state-key argument covers them too.
- **The move must be a single atomic, exclusive-access operation**: `root.hcl`'s S3-compatible
  `remote_state` block configures no lock-table equivalent, so nothing at the backend level
  arbitrates two processes touching the same state key concurrently. Combined with `terragrunt
  run-all` (the `Makefile`'s `plan-all`/`apply-all`/`run-all-*` targets, whose `ENV` defaults to
  `production`) recursively discovering every `terragrunt.hcl` under the invocation directory,
  a stale shell still `cd`'d into an old, not-yet-deleted top-level `environments/` during the
  transition window could independently compute the identical state key with no lock to prevent a
  race. U2 therefore requires the old top-level paths to be fully deleted — not just have their
  contents moved — before any `terragrunt plan`/`run-all` is run from any shell, staging or
  production.
- **The GitHub credential must be a repo-level Deploy Key, not a personal SSH key**: only a
  Deploy Key added under this specific repository's own Settings is hard-scoped by GitHub to
  read-only, single-repo git access. Attaching the new keypair as a personal account SSH key
  instead would silently grant ArgoCD's repo-server clone access to every repository that
  account can read, defeating the single-repo scoping the accepted blast-radius tradeoff (see
  Risks & Dependencies) depends on. U5 verifies this was done correctly, since GitHub gives no
  Terraform-visible signal distinguishing the two.

---

## Open Questions

### Resolved During Planning

- Exact `git mv` vs. plain `mv` sequencing for the move (origin doc's Deferred-to-Planning item
  affecting R16): `Makefile`, `README.md`, `examples/README.md`,
  `modules/gateway-api/README.md`, `modules/helm-charts/README.md`, and `setup.sh` are currently
  **untracked** in git (confirmed via `git status`); everything else in the move list is tracked.
  `README.md` stays at the true root (R17) and does not move. The other five untracked files move
  via plain `mv`/`cp` as part of their containing directory or individually (`Makefile`,
  `setup.sh`); everything tracked moves via `git mv`. A single `git add -A` after the move
  reconciles both halves into one commit.
- Whether `path_relative_to_include()`-derived S3 state keys survive the move (origin doc's other
  Deferred-to-Planning item affecting R16): yes, analytically confirmed (see Key Technical
  Decisions) — reduced from an open question to a required execution-time verification step (U2's
  Test scenarios and Approach, which capture and diff `terragrunt state list` output per stack).
- SSH deploy key vs. HTTPS token, and whether to generate a brand-new deploy key scoped to this
  repo (origin doc's Outstanding Question affecting R11/R20): a new, dedicated read-only SSH
  deploy key for this repo, generated specifically for ArgoCD's pull access — reusing the
  operator's own personal SSH key would grant ArgoCD's repo-server broader access than intended
  and mix credential lifecycles.
- Whether self-referencing introduces a new inbound network path (e.g. a GitHub webhook to
  ArgoCD): no — nothing in this repo's Terraform (no `github` provider, no webhook resource
  anywhere in `modules/argocd-gitops`) configures one, so ArgoCD stays on its default poll-based
  reconciliation against `revision = "HEAD"`; self-referencing changes an outbound credential
  (the deploy key) but adds no new inbound surface.
- Whether `docs/gitops-repo-scaffold.md` needs updating as part of this plan: yes — its opening
  paragraph currently states the GitOps repo "doesn't exist yet — create it separately," directly
  contradicting R10, and its example `terragrunt.hcl` path predates the `infra/` move. Since this
  plan's own U4 creates skeleton `README.md` files that link to it, leaving it stale would
  introduce a fresh, immediately-reachable inconsistency rather than preserve a historical one
  (see Scope Boundaries). Folded into U3.

### Deferred to Implementation

- Whether staging's `argocd-gitops` Terraform stack has already been applied with a real (or
  placeholder/empty) `gitops_repo_url` value: unknown from repo inspection alone (the value lives
  in encrypted `secrets.yaml`). U5's execution note requires checking `terragrunt plan` output
  before `apply` specifically because of this uncertainty — a placeholder-to-real-value change is
  low risk, but a real-value-to-different-real-value change would force ArgoCD to re-clone and
  re-sync every existing `Application`, which should be a deliberate, reviewed action, not a
  surprise.
- Exact GitHub UI/CLI mechanics for adding a new deploy key to this specific repo (`gh` CLI vs.
  the web UI) — an execution-time choice, not a planning one.

---

## Output Structure

    .
    ├── infra/
    │   ├── Makefile
    │   ├── setup.sh
    │   ├── root.hcl
    │   ├── secrets.yaml
    │   ├── secrets.yaml.example
    │   ├── keys.txt                       # git-ignored, not committed
    │   ├── environments/
    │   │   ├── staging/
    │   │   └── production/
    │   ├── modules/
    │   │   ├── argocd-gitops/
    │   │   ├── crds/
    │   │   ├── gateway-api/
    │   │   ├── helm-charts/
    │   │   └── karpenter/
    │   └── examples/
    ├── apps/
    │   └── README.md                      # skeleton placeholder, see docs/gitops-repo-scaffold.md
    ├── platform/
    │   └── README.md                      # skeleton placeholder, see docs/gitops-repo-scaffold.md
    ├── docs/
    ├── .sops.yaml
    ├── .gitignore
    ├── README.md
    └── AGENTS.md

---

## Implementation Units

- [x] U1. **Make the ArgoCD GitOps module topology-agnostic**

**Goal:** Replace hardcoded `apps/*`/`platform/*` ApplicationSet generator paths with configurable
variables, and reword the module's documentation so self-referencing monorepo and dedicated
split-repo read as equally supported, not "dedicated repo required."

**Requirements:** R19, R20

**Dependencies:** None

**Files:**
- Modify: `modules/argocd-gitops/variables.tf` (add `gitops_apps_path`, `gitops_platform_path`;
  reword `gitops_repo_url`'s description)
- Modify: `modules/argocd-gitops/main.tf` (replace the two hardcoded `directory { path = ... }`
  literals with the new variables)
- Modify: `modules/argocd-gitops/README.md` (reword the "Input" example and any "dedicated
  repository" framing)
- Modify: `secrets.yaml.example` (correct the stale "dedicated repo, created separately" comment
  near `gitops_repo_url` to match the reversed decision)

**Approach:**
- Add `gitops_apps_path` and `gitops_platform_path` as plain `string` variables, each defaulting
  to `"apps"` / `"platform"` respectively, in `modules/argocd-gitops/variables.tf`, following the
  exact style of the existing `gitops_repo_url` variable (description, no validation block beyond
  type).
- In `main.tf`, replace `path = "apps/*"` with an interpolated path built from
  `var.gitops_apps_path` (e.g. `"${var.gitops_apps_path}/*"`), and the `platform/*` literal
  correspondingly. Do not change any other part of the two `argocd_application_set` resources —
  the `depends_on` ordering (`argocd_project` before `argocd_repository`) documented in existing
  comments is a real, previously-discovered fix and must be preserved untouched.
- Reword `gitops_repo_url`'s variable description to state both supported topologies explicitly
  (e.g. "URL of the GitOps content repository — either this repo's own SSH URL (self-referencing
  monorepo) or a separate dedicated repo").

**Patterns to follow:**
- `modules/argocd-gitops/variables.tf`'s existing `gitops_repo_url`/`gitops_repo_ssh_private_key`
  variable declarations (plain `string`, `sensitive = true` only where warranted).

**Test scenarios:**
- Happy path: given `gitops_apps_path = "apps"` (the default), `terraform plan` against the
  module shows the `apps` ApplicationSet's `directory.path` rendering as `"apps/*"` — identical to
  today's hardcoded behavior.
- Happy path: given a non-default `gitops_apps_path = "gitops/apps"`, the rendered
  `directory.path` becomes `"gitops/apps/*"`, proving the variable is genuinely threaded through
  rather than shadowed by a leftover literal.
- Happy path: given `gitops_platform_path = "platform"` (the default), the `platform`
  ApplicationSet's `directory.path` renders as `"platform/*"` — the same coverage as
  `gitops_apps_path` above, but for the second literal this unit replaces.
- Happy path: given a non-default `gitops_platform_path = "gitops/platform"`, the rendered
  `directory.path` becomes `"gitops/platform/*"`.
- Edge case: `terraform fmt -check` on `modules/argocd-gitops` reports no formatting drift
  introduced by the new variable/expression additions (a standalone `terraform validate`/`init`
  is not meaningful here — see Verification).

**Verification:**
- No module in this repo (`crds`, `gateway-api`, `helm-charts`, `karpenter`, `argocd-gitops`)
  declares its own `required_providers` — that comes only from Terragrunt's `generate "providers"`
  block at the stack level, so a standalone `terraform validate`/`init` against
  `modules/argocd-gitops` fails immediately with a missing-provider error and is not a meaningful
  check on its own. Genuine behavioral proof that the two new variables are threaded through
  belongs to U4's stack-level `terragrunt validate`/`plan` (`cd
  infra/environments/staging/argocd-gitops`), which already claims this coverage in its own Test
  scenarios.
- For this unit alone, verification is a manual diff review confirming the only functional change
  to `main.tf` is the two `directory.path` expressions — no other resource attributes shifted.

---

- [x] U2. **Relocate all Terraform/Terragrunt content into `infra/`**

**Goal:** Move `environments/`, `modules/`, `root.hcl`, `Makefile`, `setup.sh`, `examples/`,
`secrets.yaml`, `secrets.yaml.example`, and `keys.txt` into a new top-level `infra/` directory,
preserving their structure and relative nesting to each other exactly, including git-ignored
working files that live alongside them.

**Requirements:** R16, R17, R18 (this unit's "do not move `.sops.yaml`" instruction is what
structurally satisfies R18, even though R18 itself has no dedicated content change)

**Dependencies:** U1 must land first. U1 edits `modules/argocd-gitops/{variables.tf,main.tf,README.md}`
and `secrets.yaml.example` at their **pre-move** paths; this unit relocates those same files into
`infra/`. Running U2 before U1 would leave U1 editing paths that no longer exist.

**Files:**
- Move (git-tracked, via `git mv`): `root.hcl`, `secrets.yaml`, `secrets.yaml.example`,
  `environments/**` (all tracked contents), `modules/**` (all tracked contents), `examples/**`
  (all tracked contents except its own untracked `README.md`, moved alongside per the next
  bullet)
- Move (currently untracked, via plain `mv`): `Makefile`, `setup.sh`, `examples/README.md`,
  `modules/gateway-api/README.md`, `modules/helm-charts/README.md` (the latter three move as part
  of their parent directories' move)
- Move (git-ignored working files, filesystem-level only — `git mv` will not touch these):
  `keys.txt`, `environments/staging/kubeconfig-staging`,
  `environments/staging/kubeconfig-staging.bak`, `environments/staging/talosconfig-staging`,
  `environments/staging/talosconfig-staging.bak`,
  `environments/staging/kubernetes-cluster/talosconfig-staging`,
  `environments/staging/argocd-gitops/.argocd-admin-password`, and every `.terraform.lock.hcl` /
  `.terragrunt-cache/` under `environments/**` (or simply regenerate the latter two post-move via
  `terragrunt init -reconfigure` per stack, since the `Makefile`'s own `clean` target already
  treats them as disposable)
- Do not move: `apps/`, `platform/`, `docs/`, `.sops.yaml`, `.gitignore`, `README.md`, `AGENTS.md`

**Approach:**
- Before any `git mv`, capture a pre-move baseline for every Terragrunt stack in both
  environments (staging **and** production — all four production stacks plus staging's five move
  too, even though only staging has an `argocd-gitops` stack): record `terragrunt state list`
  output per stack. This is the diffable baseline the post-move verification compares against —
  a no-op `terragrunt plan` alone is a weaker signal, since a wrong/empty backend key does not
  error, it silently starts from empty state.
- Move `keys.txt` and `environments/staging/argocd-gitops/.argocd-admin-password` first, before
  the rest of the git-ignored working files, and verify both exist at their new `infra/`-relative
  path before proceeding. `.argocd-admin-password` has an asymmetric blast radius: it's fetched
  from the live `argocd-initial-admin-secret` Kubernetes Secret, which is commonly deleted after
  first login as an ArgoCD hardening practice — if that secret is already gone and this local
  file is lost or misplaced during the move, recovery requires live-cluster credential
  remediation, not just re-running a `before_hook`. `kubeconfig-staging`/`talosconfig-staging`,
  by contrast, are regenerated automatically on the next `kubernetes-cluster` apply, so a fumbled
  move of those two is self-healing.
- Create `infra/`, then move the tracked half with `git mv` (preserves history) and the untracked
  half with plain `mv`, then move every remaining git-ignored working file at the filesystem
  level so nothing operational is silently left behind at the old path. Before the final
  `git add -A`, review the new commit's file list for any `.gitignore`d filename (`keys.txt`,
  `kubeconfig*`, `talosconfig*`, `.argocd-admin-password`) — self-referencing this repo as the
  live ArgoCD GitOps source (U5) means an accidental plaintext-secret commit during this bulk
  move would become reachable via both a future `git clone` and ArgoCD's own repo-browse UI, not
  just `git clone` as it would have been before this plan. Finish with `git add -A` so the move
  lands as a single coherent change covering both halves.
- Do not touch `.gitignore` — every pattern it defines (bare filenames and `**/`-prefixed globs)
  already matches these files at any depth, so no rule updates are needed for them to keep being
  ignored under `infra/`.
- Verify no stray leftover files remain at the old top-level `environments/`, `modules/`,
  `examples/` paths after the move (including the empty, untracked
  `environments/production/karpenter`/`karpenter-helm` scratch directories noted during research —
  confirm intentionally whether these should be recreated under `infra/environments/production/`
  or left behind as abandoned scratch space). This is a hard precondition, not just tidiness: the
  old top-level paths must be **fully deleted**, not merely emptied of the files that moved,
  before any `terragrunt plan`/`run-all` is executed from any shell (see Key Technical Decisions'
  atomicity note) — a stray leftover `terragrunt.hcl` at the old path would let a stale shell
  independently discover it and race the new tree for the same state key.

**Test scenarios:**
- Happy path: after the move, `find . -maxdepth 1` shows no remaining top-level
  `environments/`, `modules/`, `root.hcl`, `secrets.yaml`, `Makefile`, `setup.sh`, or `examples/`
  entries outside `infra/`.
- Edge case: `keys.txt` and every git-ignored working file listed above exist at their new
  `infra/`-relative path and nowhere else (`find . -iname 'kubeconfig*' -o -iname 'talosconfig*'
  -o -iname 'keys.txt'` returns only paths under `infra/`).
- Edge case: the empty `environments/production/karpenter`/`karpenter-helm` scratch directories
  have an explicit, deliberate disposition after the move (either recreated under
  `infra/environments/production/` or confirmed intentionally abandoned) — not silently dropped
  by the move mechanics without a decision being made.
- Integration: `git status` after `git add -A` shows the tracked files as renames
  (`R` status, not delete+add) for every file moved via `git mv`, confirming history was
  preserved, and shows the previously-untracked files as new additions at their `infra/` paths.
- Integration: the pre-move `terragrunt state list` output for every stack in both staging and
  production matches the post-move output exactly (same resource addresses, same count) — this
  is the concrete check the state-key-stability claim in Key Technical Decisions rests on, not
  just a no-op `plan`.

**Verification:**
- No file that should have moved remains at its old top-level location; no file that should have
  stayed at the true root moved.
- `git log --follow infra/root.hcl` (and similarly for a couple of other moved files) shows
  history continuity from before the move.
- The new move commit's file list contains no `.gitignore`d filename (spot-checked against
  `.gitignore`'s patterns).

---

- [x] U3. **Repair path references broken or made stale by the move**

**Goal:** Update every documented command, script, and doc-prose reference that assumed
Terraform/Terragrunt content lived at the true repo root, so the repo's onboarding and operational
instructions are correct post-move.

**Requirements:** R16, R17 (downstream correctness of the move)

**Dependencies:** U2

**Files:**
- Modify: `AGENTS.md` (validation-prerequisites `SOPS_AGE_KEY_FILE` line; every
  `cd environments/<env>/<module>` validation command; the "run all commands from the repository
  root" note, re-scoped to describe the two-root layout)
- Modify: `README.md` (repository-layout ASCII tree — restructure to show `infra/` nesting plus
  the new `apps/`/`platform/` entries and the `docs/` entry it was already missing; quickstart's
  `./setup.sh` invocation; both occurrences of the hardcoded absolute
  `SOPS_AGE_KEY_FILE="/home/berk/hetznerk8s/keys.txt"` path, switched to the same portable
  `$(git rev-parse --show-toplevel)/infra/keys.txt` form `AGENTS.md` already uses — not a literal
  `infra/`-spliced absolute path, which would preserve the pre-existing non-portability defect;
  the deployment-order example's first
  `cd environments/staging/kubernetes-cluster`; the Common Make targets section, switched to the
  `make -C infra <target> ...` form per Key Technical Decisions)
- Modify: `infra/setup.sh` (the `.sops.yaml` `sed` target path, changed to
  `$(git rev-parse --show-toplevel)/.sops.yaml`; the final "Next steps" message's
  `cd environments/production/kubernetes` — both the missing `infra/` prefix and the
  `kubernetes` → `kubernetes-cluster` typo; the stale `TERRAGRUNT_README.md` reference, corrected
  to `README.md`)
- Modify: `infra/modules/gateway-api/README.md` (its own `cd environments/<env>/kubernetes-cluster`
  example command, prefixed with `infra/`)
- Modify: `docs/gitops-repo-scaffold.md` (its opening paragraph currently states the GitOps repo
  "doesn't exist yet — create it separately," directly contradicting R10; reword to reflect that
  this repo is now the GitOps repo; update its `environments/staging/argocd-gitops` path reference
  to `infra/environments/staging/argocd-gitops`; and update its two "pre-migration" mentions of
  `environments/staging/env.hcl` to the `infra/`-prefixed path as well)
- Modify: `docs/solutions/integration-issues/argocd-provider-config-path-tls-cert-verification-failure-2026-07-31.md`
  (its `environments/staging/argocd-gitops/terragrunt.hcl` path reference, updated to the `infra/`
  prefix — this plan cites this exact document in its own Institutional Learnings section, so
  leaving its path stale would be an inconsistency this plan itself introduces, not a pre-existing
  one)

**Approach:**
- Treat `AGENTS.md` and `README.md` together first — their `cd environments/...` and
  `SOPS_AGE_KEY_FILE` lines are near-duplicates and can be fixed with the same
  `environments/` → `infra/environments/` and `keys.txt` → `infra/keys.txt` substitutions, but the
  README's repo-layout tree and hardcoded absolute paths still need manual, non-mechanical
  rewrites.
- `infra/modules/gateway-api/README.md`'s own example command needs the identical `infra/` prefix
  treatment as `AGENTS.md`/`README.md` — it's the one module-level README (of `crds`, `gateway-api`,
  `helm-charts`, `karpenter`, `argocd-gitops`) that contains a stale root-relative example.
- `infra/setup.sh`'s fix is the one genuine behavioral repair in this unit (not just doc
  staleness): after the move, `.sops.yaml` no longer sits in `setup.sh`'s own working directory,
  so its `sed -i.bak` must reference the file by an explicit, portable path rather than a bare
  filename.
- `Makefile` itself needs **no internal edits** — its `cd environments/$(ENV)/$(MODULE)` targets
  already resolve correctly relative to wherever `make` is invoked from, and `make -C infra`
  changes that directory before the targets run.

**Test scenarios:**
- Happy path: running the documented validation workflow verbatim from a clean checkout
  (`export SOPS_AGE_KEY_FILE=...`, `cd infra/environments/staging/kubernetes-cluster && terragrunt
  init -reconfigure && terragrunt validate`) succeeds using only the paths written in the updated
  `AGENTS.md`/`README.md`.
- Edge case: running `infra/setup.sh` from a fresh clone correctly locates and edits the true-root
  `.sops.yaml`, not a nonexistent `infra/.sops.yaml`.
- Error path (regression check): confirm `infra/setup.sh` fails loudly (non-zero exit, clear
  message) rather than silently no-op-ing if `.sops.yaml` cannot be found at the expected path —
  guards against the exact silent-failure risk this fix addresses.

**Verification:**
- Every command example in `README.md`/`AGENTS.md` is copy-paste runnable against the moved tree.
- `infra/setup.sh` run end-to-end on a scratch clone produces a correctly-encrypted `secrets.yaml`
  and a correctly-updated `.sops.yaml` at the true root.

---

- [x] U4. **Wire the new path variables through the staging stack and add the `apps/`/`platform/` skeleton**

**Goal:** Thread `gitops_apps_path`/`gitops_platform_path` from `env.hcl` through the
`argocd-gitops` Terragrunt stack into the module (U1's variables), and create the top-level
`apps/`/`platform/` directory skeletons at the true repo root.

**Requirements:** R17, R19 (satisfied at the module level by U1 alone; this unit's inclusion of
R19 is about making the non-default path *reachable* from the environment layer, not extending
R19's scope — without this wiring, an operator could never actually pass a non-default
`gitops_apps_path`/`gitops_platform_path` for staging even though the module supports it)

**Dependencies:** U1, U2

**Files:**
- Modify: `infra/environments/staging/env.hcl` (add `gitops_apps_path`/`gitops_platform_path` to
  `inputs`, defaulting to `"apps"`/`"platform"`)
- Modify: `infra/environments/staging/argocd-gitops/terragrunt.hcl` (thread the two new inputs
  from `include.env.inputs.*` into the module, alongside the existing `gitops_repo_url` wiring)
- Create: `apps/README.md` (skeleton placeholder — states the directory's purpose and links to
  `docs/gitops-repo-scaffold.md`)
- Create: `platform/README.md` (same, for the `platform` tier)

**Approach:**
- Mirror the exact `inputs = { gitops_repo_url = include.env.inputs.gitops_repo_url, ... }`
  pattern already present in `infra/environments/staging/argocd-gitops/terragrunt.hcl` for the two
  new variables — no new plumbing pattern needed.
- The two skeleton `README.md` files are intentionally minimal: enough to make `apps/`/`platform/`
  git-trackable and self-explanatory, not a preview of the eventual scaffold content.

**Test scenarios:**
- Happy path: `terragrunt validate` for `infra/environments/staging/argocd-gitops` succeeds with
  the two new inputs present, using their default values.
- Integration: a `terragrunt plan` (not just `validate`) for this stack, run against the live
  cluster, shows **no diff at all** outside the two `ApplicationSet` resources' `directory.path`
  expressions, and no diff on those either — the defaults render to the identical `"apps/*"`/
  `"platform/*"` strings before and after wiring — confirming no unintended resource replacement
  is triggered by wiring alone.
- Edge case: `apps/README.md` and `platform/README.md` are created, tracked in git, and each
  contains a working relative link to `docs/gitops-repo-scaffold.md`.

**Verification:**
- `apps/README.md` and `platform/README.md` exist at the true repo root and are tracked in git.
- The staging `argocd-gitops` stack's Terraform state shows no unexpected diff from this unit
  alone (path variables at their defaults should be a no-op against live state).

---

- [x] U5. **Repoint staging's ArgoCD GitOps registration to self-reference this repo**

**Goal:** Update `gitops_repo_url` (and its SSH credential) in staging's encrypted `secrets.yaml`
so the live `argocd_repository`/`ApplicationSet` resources point at this repo instead of an
unresolved placeholder or a never-created separate repo, using a newly generated, dedicated
read-only deploy key.

**Requirements:** R10, R11

**Dependencies:** U1, U4

**Files:**
- Modify: `infra/secrets.yaml` (update `gitops_repo_url` to this repo's own SSH URL and
  `gitops_repo_ssh_private_key` to the new deploy key's private half — via `sops`, never
  hand-edited in plaintext; also correct the real file's comment preceding `gitops_repo_url` that
  mirrors `secrets.yaml.example`'s stale "dedicated repo, created separately" framing, since U1
  only fixes the `.example` template's copy, not the live encrypted file)

**Approach:**
- Generate a new, dedicated read-only SSH deploy key (not the operator's personal key) scoped to
  this repository, add its public half under this specific repository's own GitHub Settings ->
  Deploy Keys (read-only, not a personal-account SSH key — see Key Technical Decisions), and store
  the private half in `infra/secrets.yaml` via `sops`.
- `var.gitops_repo_url` is consumed by three resources in one apply graph, not one:
  `argocd_repository.gitops`, and both `argocd_application_set.apps`/`.platform`'s
  `generator.git.repo_url` *and* per-Application `template.spec.source.repo_url`. Before applying,
  run `terragrunt plan` for `infra/environments/staging/argocd-gitops` and inspect the diff across
  all three: if `gitops_repo_url` was previously unset/placeholder, expect all three to go from
  not-existing (or empty) to created; if it previously held a real (if never-populated)
  separate-repo value, expect an in-place update across all three consistently (a diff touching
  only some of the three would itself be a signal something is wrong before `apply` even runs).
- Before `apply`, separately check the *current live* Application inventory (e.g. `kubectl get
  applications -n argocd` or an equivalent ArgoCD CLI/API call) — a Terraform plan diff only shows
  attribute changes on the three Terraform-managed resources above; it has no visibility into
  which Applications the ApplicationSet controller has already generated from the old URL, or
  whether any would be pruned/orphaned once the generator's `repo_url` changes. This is a separate,
  necessary precondition, not something the Terraform plan review above can substitute for.
- After `apply`, confirm exactly one repository entry exists for the intended URL (via `argocd
  repo list` or equivalent), not a leftover entry for the old URL — the `argocd_repository`
  resource's `Update()` behavior on a URL change has not been verified to explicitly deregister
  the prior URL server-side; treat this as an explicit post-apply check rather than an assumption.

**Execution note:** Verify with a real `terragrunt apply` against the live cluster, not just
static `validate`/`plan` — this stack's ArgoCD provider block has a previously-documented TLS
regression risk (see Institutional Learnings) that only manifests at live apply time.

**Test scenarios:**
- Happy path: after `apply`, `argocd repo list` (or the ArgoCD UI) shows this repository
  registered and reachable via the new deploy key, with no stale entry remaining for whatever
  `gitops_repo_url` held before this unit.
- Edge case: the new deploy key's public half is confirmed to be attached as this specific
  repository's own read-only Deploy Key (GitHub Settings -> Deploy Keys), not as a personal-account
  SSH key under the operator's GitHub profile — the single-repo, read-only scoping this plan's
  accepted blast-radius tradeoff depends on only holds if this distinction is verified, not
  assumed.
- Regression check: the stack's generated `providers.tf` still contains the explicit
  `kubernetes { host, cluster_ca_certificate, client_certificate, client_key }` block (not a bare
  `config_path`) after `apply` completes successfully — directly exercising the previously-
  documented TLS/`config_path` failure mode this unit's Execution note calls out, rather than
  leaving that check solely to Verification.
- Integration: the `apps`/`platform` `ApplicationSet`s successfully poll this repo's `apps/*` and
  `platform/*` paths (currently just the two skeleton `README.md` files, so no `Application`
  objects are expected to be generated yet — this proves connectivity without requiring real
  content).
- Error path: if the deploy key is misconfigured (wrong repo, revoked, or read-only enforcement
  misapplied), `terragrunt apply` surfaces a clear git-authentication failure from the `argocd`
  provider rather than a silent no-op.

**Verification:**
- ArgoCD's registered repository list shows exactly one entry for this repo's URL with a
  successful connection status — no duplicate or stale old-URL entry.
- No regression of the documented TLS/`config_path` issue — the stack's generated `providers.tf`
  still uses the explicit `kubernetes { host, cluster_ca_certificate, client_certificate,
  client_key }` block, unchanged.
- The pre-apply live Application inventory check and its outcome (empty / non-empty, and if
  non-empty, what happened to those Applications post-apply) is recorded, not just performed.

---

## System-Wide Impact

- **Interaction graph:** No new Terragrunt dependency edges — `argocd-gitops` continues to depend
  on `kubernetes-cluster` and `helm-charts` exactly as before; only the *location* of the stacks
  changes, not their dependency graph. No Terraform-managed `argocd-gitops` resource
  (`argocd_repository`, `argocd_project.apps`/`.platform`, `argocd_application_set.apps`/`.platform`)
  is itself expressed as a manifest under `apps/**`/`platform/**` — ArgoCD is never asked to
  reconcile the objects that define its own sync source, so no literal self-management/sync loop
  is introduced. Recovery of the `argocd-gitops` stack itself (e.g. after state corruption or a
  recurrence of the TLS issue below) must always go through Terraform, not a commit to
  `apps/`/`platform/` — GitOps can bootstrap ordinary apps, but it can never bootstrap the
  Terraform-managed control objects GitOps itself depends on. No GitHub webhook or other new
  inbound path is introduced (see Open Questions) — reconciliation stays ArgoCD's default
  poll-based model against `revision = "HEAD"`.
- **State lifecycle risks:** Remote state keys are provably unchanged (see Key Technical
  Decisions), verified concretely in U2 via a `terragrunt state list` diff, not just a no-op
  `plan`. `root.hcl`'s S3 backend configures no lock-table equivalent, so the move must be a
  single atomic, exclusive operation (see Key Technical Decisions). U5's `gitops_repo_url` change
  is **not** a single-resource credential rotation — it's consumed by three resources
  (`argocd_repository` plus both `ApplicationSet`s' generator and template `repo_url` fields) in
  one apply graph; a partial apply across this graph could leave a split-brain state (e.g. the
  repository updated while an `ApplicationSet` still references the old value). U5's Approach adds
  an explicit cross-resource diff review and a pre/post-apply Application-inventory check for
  exactly this reason — a Terraform plan diff alone cannot see the ApplicationSet-controller-side
  reconciliation consequence, which happens independently in-cluster once `apply` completes.
- **API surface parity:** `modules/argocd-gitops`'s public variable surface gains two new optional
  variables with backward-compatible defaults — any future consumer of this module (in a split-repo
  topology) sees no breaking change.
- **Integration coverage:** Both U4's `terragrunt plan` (which triggers the `argocd` provider's
  refresh against the live ArgoCD API) and U5's `apply` exercise the live ArgoCD API — the real
  distinction is that only U5 performs a state-mutating `apply`, not that U5 is uniquely
  live-API-touching.
- **Unchanged invariants (configuration level):** The two `AppProject`s' trust-tier boundaries
  (cluster-resource whitelist/blacklist) and the Sealed Secrets deferred-deployment decision are
  untouched by this plan's code changes. The KSOPS repo-server patch's *configuration* is also
  unchanged — but see the next bullet for why its *effective* exposure is not.
- **Changed trust boundaries (this plan's most significant architectural effect, not an
  invariant):** ArgoCD's repo-server read-access boundary expands from what would have been a
  dedicated GitOps-only repo to this entire monorepo — `infra/`'s Terraform source and
  `infra/secrets.yaml`'s SOPS ciphertext included (see Risks & Dependencies for the accepted
  read-breadth tradeoff and the separately-mitigated write/escalation axis). The KSOPS
  repo-server patch's *mount mechanism* is already live (a Kubernetes Secret sourced from
  `platform_sops_age_private_key`), but that key's actual value is still a placeholder as of this
  plan (see Scope Boundaries) — so the platform-tier/Terragrunt-secrets blast-radius collapse
  described in the origin brainstorm becomes real only once a genuine key is generated, not yet.
  `sync_policy.automated.self_heal` on both `ApplicationSet`s is unchanged as code but goes from
  practically dormant (while `gitops_repo_url` is unset/placeholder, pre-U5) to live for the first
  time as of U5 — a runtime behavioral activation, not merely a configurability change.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Git-ignored operational files (`kubeconfig-staging`, `.argocd-admin-password`, Terraform caches) silently left behind at the old path since `git mv` doesn't touch untracked files; `.argocd-admin-password` in particular has an asymmetric blast radius — recoverable only via live-cluster credential remediation, not a re-apply, if ArgoCD's initial-admin secret has already been deleted in-cluster | U2 explicitly filesystem-moves every git-ignored working file, moving `keys.txt`/`.argocd-admin-password` first and verifying their presence at the new path before the rest of the move proceeds |
| `setup.sh`'s `.sops.yaml` reference silently breaks (wrong cwd assumption) once `setup.sh` moves but `.sops.yaml` doesn't | U3 replaces the bare filename reference with a `git rev-parse --show-toplevel`-based path, matching `AGENTS.md`'s existing portable convention |
| Regression of the documented ArgoCD provider TLS/`config_path` issue if the `argocd-gitops` stack's generated provider block is touched carelessly during the move or the U1/U4/U5 changes | U1/U4 changes are scoped to variables and generator paths only, not the provider block; U5 adds a dedicated test scenario plus its Execution note requiring a live `terragrunt apply` verification, not just static validate |
| No remote-state locking is configured (`root.hcl`'s S3 backend has no lock-table equivalent), and `terragrunt run-all` (the `Makefile`'s `plan-all`/`apply-all`/`run-all-*` targets, whose `ENV` defaults to `production`) recursively discovers every `terragrunt.hcl` under the invocation directory — a stale shell still in an old, not-fully-deleted `environments/` path could race the new tree for the same state key | U2 treats the move as a single atomic, exclusive operation, requires the old top-level `environments/`/`modules/` paths fully deleted (not just emptied) before any `plan`/`run-all` runs anywhere, and captures a `terragrunt state list` baseline per stack (staging **and** production) to diff post-move |
| U5's `gitops_repo_url` change affects three resources in one apply graph (`argocd_repository` plus both `ApplicationSet`s' generator and template `repo_url`), and a Terraform plan diff cannot show the ApplicationSet-controller-side reconciliation impact (which Applications get pruned or orphaned) or confirm the provider's `Update()` doesn't leave a stale old-URL repository entry | U5 adds an explicit pre-apply live Application-inventory check and a post-apply single-repository-entry check, not just a Terraform plan review |
| Deploy key for the self-referenced repo grants read-breadth access to the entire monorepo (Terraform source, encrypted secrets ciphertext) via git clone, **and separately** via ArgoCD's own repo-browse UI/API to any actor with Application-view/create RBAC — a broader, different population than deploy-key holders | Read-breadth exposure is an accepted tradeoff (single-operator repo, no team access-control layer today) with no further mitigation; the write/escalation axis is separately mitigated by a dedicated, repo-level, read-only GitHub Deploy Key (U5 verifies this specific attachment mechanism, not a personal SSH key) |
| GitHub deploy key's read-only flag can be toggled post-creation outside Terraform (no `github` provider manages it here), with no drift signal in this repo | Documented as a manual periodic re-check in `README.md`'s operational notes — no automated detection exists |
| Self-referencing collapses two previously-separate blast radii: the mounted platform-tier AGE key and the Terragrunt/root secrets now share one exec-capable `argocd-repo-server` process/filesystem context; this is reachable not only via a less-trusted collaborator's write access, but also via a compromise of the repo-server itself while processing untrusted chart/plugin content under `apps/*`/`platform/*` (a documented ArgoCD attack-surface category) | Accepted for the current single-operator setup; reaffirmed as a prerequisite to resolve (e.g. a pre-sync policy restricting exec-plugin/KSOPS usage to `platform/*`) before granting any less-than-fully-trusted collaborator write access **or** before accepting third-party chart/plugin sources under `apps/`/`platform/` |
| The new deploy key's private half, once live in U5, is stored in Terraform state (which retains all attribute values in plaintext, `sensitive = true` only redacts CLI/plan output) as well as in encrypted `secrets.yaml` — the S3-compatible state backend's own encryption-at-rest and access scoping predate this plan and are outside its file-editing scope, but U5 is the point where a placeholder becomes a live, functioning credential worth protecting | Out of scope for this plan to change; flagged here so the operator can confirm the existing state backend's access controls are adequate now that it holds a working credential, not a placeholder |
| Accidental plaintext-secret commit during U2's bulk `git add -A` (moving `keys.txt`/kubeconfigs alongside tracked files) becomes reachable via both git clone and ArgoCD's repo-browse UI post-U5, not just git clone as before this plan | U2's Approach and Verification add an explicit pre-`git add -A` review of the move's file list for any `.gitignore`d filename |
| Empty, untracked `environments/production/karpenter`/`karpenter-helm` scratch directories may be silently dropped or inconsistently carried by a naive move | U2 explicitly calls out verifying these directories' fate rather than assuming a directory-level `mv` handles them correctly |

---

## Sources & References

- **Origin document:** [docs/brainstorms/argocd-gitops-migration-requirements.md](../brainstorms/argocd-gitops-migration-requirements.md)
- Prior, already-merged plan: [docs/plans/2026-07-30-001-feat-argocd-gitops-migration-plan.md](2026-07-30-001-feat-argocd-gitops-migration-plan.md)
- GitOps content scaffold (for the follow-up work this plan defers): [docs/gitops-repo-scaffold.md](../gitops-repo-scaffold.md)
- Institutional learning: [docs/solutions/integration-issues/argocd-provider-config-path-tls-cert-verification-failure-2026-07-31.md](../solutions/integration-issues/argocd-provider-config-path-tls-cert-verification-failure-2026-07-31.md)
- Related code: `root.hcl`, `modules/argocd-gitops/main.tf`, `modules/argocd-gitops/variables.tf`,
  `environments/staging/argocd-gitops/terragrunt.hcl`, `environments/staging/env.hcl`,
  `AGENTS.md`, `README.md`, `setup.sh`, `Makefile`
