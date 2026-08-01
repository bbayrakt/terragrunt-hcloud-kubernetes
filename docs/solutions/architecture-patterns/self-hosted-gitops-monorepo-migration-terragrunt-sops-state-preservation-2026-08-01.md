---
title: Self-Hosted GitOps Monorepo Migration — Preserving Terragrunt State and SOPS Resolution
date: 2026-08-01
category: architecture-patterns
module: repo-monorepo-migration
problem_type: architecture_pattern
component: tooling
severity: high
applies_when:
  - "Moving Terraform/Terragrunt (or any IaC) content into a subdirectory of an existing repo, or converting a single-purpose repo into a monorepo layout"
  - "A 'content repo' a system depends on (GitOps manifests, Helm chart source, config bundles) turns out not to exist separately and gets folded into the infra repo instead"
  - "Adding configurability to a previously hardcoded path, credential, or auth-mode in a Terraform module, especially where two or more variables jointly encode an invariant"
  - "Touching a bash script that assigns a command substitution to a variable under `set -e`, especially in setup/bootstrap scripts meant to fail loudly"
  - "A script creates a `.bak`/backup copy of a file that contains secrets"
  - "About to trust a planning/status document's claim that something is 'already done' for live infrastructure or a live secret"
  - "Introducing a CRD and a custom resource that depends on it via `kubernetes_manifest` in Terraform, for a target cluster that might not have the CRD yet"
  - "Code review on Terraform modules exposing multiple auth modes or path-based trust boundaries"
related_components:
  - argocd-gitops-stack
tags: [monorepo, terragrunt, gitops, argocd, sops, secrets-management, remote-state, set-e]
---

# Self-Hosted GitOps Monorepo Migration — Preserving Terragrunt State and SOPS Resolution

## Context

This repo shipped a two-tier `AppProject`/`ApplicationSet` ArgoCD architecture
(`infra/modules/argocd-gitops`) under the assumption that application manifests (`apps/`,
`platform/`) would live in a **separate**, dedicated GitOps repository — the original brainstorm
explicitly noted that repo "doesn't exist yet, create it later" (session history, 2026-07-30).
That separate repo was never created. By the next working session it still didn't exist, and the
scaffold doc, the requirements doc, and the live Terraform (`gitops_repo_url`, SSH deploy-key auth)
all still assumed it. That gap is what forced the reversal: **make this same repo self-host its
own GitOps content** instead — turning it into a monorepo where Terraform/Terragrunt lives under
`infra/` and the ArgoCD-watched manifests (`apps/`, `platform/`) stay at the true repository root.

Getting this right required correctly reasoning about three independent path-resolution systems
that each silently assume a fixed relationship between "repo root" and "tool config root":
Terragrunt's `path_relative_to_include()` / `find_in_parent_folders()` (resolved relative to
`root.hcl`'s own location, not the filesystem root), SOPS's upward directory walk for `.sops.yaml`
discovery, and a bash script's own `git rev-parse --show-toplevel` (silently changes meaning once
invoked from a different directory). It also required moving 381 files with git history preserved
and zero count drift, proving remote state was untouched, adding three ArgoCD credential modes,
fixing several bash/security defects found in review, and deploying a real cluster end-to-end to
verify the whole thing empirically rather than by inspection alone.

## Guidance

1. **Moving an IaC tree into a subfolder is safe for remote state only if you verify it, not
   because it "should" be safe.**
   - Use `git mv` (not copy+delete) so history is preserved per-path.
   - Capture `terragrunt state list` (or equivalent) per stack *before* the move.
   - After moving, re-run it per stack and diff line-for-line against the pre-move capture. Any
     drift means the state key changed — fix it (`terragrunt state mv` / manual backend-key
     surgery) before applying anything.
   - This is safe by construction only if the whole tree — `root.hcl` and every leaf config —
     moves together, preserving relative depth. `path_relative_to_include()` /
     `find_in_parent_folders()` resolve relative to where `root.hcl` itself sits, not the
     git/filesystem root, so moving only part of the tree, or changing relative depth between
     `root.hcl` and a leaf config, silently changes derived state keys.
   - Confirm file-count parity explicitly (`find <before> | wc -l` vs. `find <after> | wc -l`, or
     `git diff --stat` on the move commit) as a cheap guard against files being dropped or
     duplicated during a bulk move.

2. **Config files "discovered" by upward directory search must stay wherever their consumers need
   to find them, not wherever feels topically tidy.**
   - `.sops.yaml` is resolved by SOPS walking *upward* from the encrypted file's own directory
     until it finds one. Moving it into a subfolder makes it invisible to any encrypted file
     living in a sibling subtree that isn't itself inside that subfolder.
   - Rule of thumb: any "upward-search" config (`.sops.yaml`, `.gitignore`, `.editorconfig`, etc.)
     must live at or above the shallowest directory of anything that needs to see it — don't move
     it just because a refactor is nominally relocating "config for the infra folder."

3. **Terraform module inputs that encode directory structure must be variables, not literals, the
   moment more than one physical layout is plausible.** Add `validation` blocks for single-variable
   shape constraints, and `lifecycle { precondition { ... } }` blocks for invariants that depend on
   more than one variable together (e.g. "these two paths must differ").

4. **When adding multiple mutually exclusive auth modes to one resource, enumerate the invalid
   combinations explicitly and reject them at plan time** rather than relying on unvalidated
   precedence. This gap is a classic silent-misconfiguration trap — independent reviewers across
   correctness, security, maintainability, and adversarial lenses converge on it every time.
   - A publicly readable HTTPS Git repo needs *no* stored credential at all for ArgoCD to clone it
     (confirmed against the `argoproj-labs/argocd` provider's own docs) — treat "no credentials" as
     a first-class third mode, not a fallback/error state.

5. **`set -e` does not protect a script the way people assume when a subshell command is assigned
   to a variable.** `X="$(cmd_that_fails)"` under `set -e` aborts the entire script immediately —
   any subsequent "did it fail" check is dead code. Fix: move the assignment into the condition of
   an `if`, since `set -e` does not trigger there.

6. **Any `mv`/`cp`/`sed -i.bak` step touching a secret file must be checked against `.gitignore`
   for the exact derived filename, not the base name.** A `keys.txt` ignore rule doesn't cover
   `keys.txt.backup`; a `secrets.yaml` rule doesn't cover `secrets.yaml.bak`. Prefer backing up
   outside the repo entirely (`mktemp -d`), and `rm -f` any `.bak` immediately after a successful
   in-place edit rather than relying on ignore patterns.

7. **Don't trust planning-doc claims of "already applied" / "already exists" for infrastructure or
   secrets — verify against the live system.** `terragrunt state list` is ground truth for "does
   this exist," not a doc saying so. For a secret claimed "already set," decrypt and check the
   actual value — a key can be present and non-empty while still holding a literal placeholder
   string from an `.example` template.

8. **`kubernetes_manifest` CRD + CR chicken-and-egg on a fresh cluster is a known provider
   limitation, not a config bug.** A CRD and any CR that depends on its schema can't be planned
   together in one pass on a cluster where the CRD doesn't exist yet. Fix: `-target`-scoped apply
   for the CRD-producing resources first, then a normal full apply.

9. **New `argocd_project`/`argocd_application_set` resources need explicit `depends_on` between
   them** *(session history)* — Terraform's default parallel creation can race an `ApplicationSet`
   against the `AppProject` it references, failing with "references project X which does not
   exist." The same class of race applies to `argocd_repository` if an `ApplicationSet`'s
   generator references a repo URL not yet registered.

10. **Verify Terraform provider schemas against `terraform validate`, not documentation or
    inference** *(session history)* — `managed_namespace_metadata` is not a field on
    `argocd_project`; it lives per-`Application`, nested under the `ApplicationSet` template's
    `sync_policy`. Both a wrong-resource-level guess and the correct nesting were only resolved by
    running real schema validation against the live provider.

## Why This Matters

- **State-key drift from a careless move is a production-outage-class mistake.** If Terraform
  loses track of an existing resource's state key, the next `apply` tries to recreate real
  infrastructure instead of managing what already exists. This is the single highest-severity risk
  in any "reorganize the repo" change to an IaC codebase, and it is only provably safe when checked
  against a live state-list diff, not by reasoning about path semantics on paper.
- **A misplaced `.sops.yaml` fails silently and asymmetrically.** Encryption of files that still
  find the config keeps working; a new file in a sibling tree fails or encrypts against the wrong
  rule — and that failure won't surface until someone adds the first secret in that sibling tree,
  likely long after the refactor is forgotten.
- **`set -e` swallowing a command-substitution failure defeats the safeguard it was protecting.**
  The whole point of a "refuse to silently skip" check is to fail loudly — a bug that aborts the
  script even more silently one line earlier is worse than the failure mode it was meant to
  prevent.
- **Plaintext secret backups outside `.gitignore` are a real credential-leak vector.** A
  `sed -i.bak` leaving a live cloud API token in an un-ignored file is one `git add -A` away from
  permanent exposure in git history.
- **Unvalidated mutually exclusive config produces "it looked like it worked" bugs** that surface
  later as unexplained behavior (wrong credential silently preferred, or a trust boundary silently
  defeated by two paths resolving to the same value) rather than as an immediate, loud plan-time
  error.
- **Trusting planning docs over live state produces wasted work or wrong conclusions** — proceeding
  as if infrastructure or a key already existed leads to applying against nothing, or encrypting
  against a key nobody can actually decrypt with.

## When to Apply

See `applies_when` in the frontmatter for the condensed list.

## Examples

### 1. Terragrunt state-key stability reasoning

```hcl
# infra/root.hcl
remote_state {
  config = {
    key = "${path_relative_to_include()}/terraform.tfstate"
    ...
  }
}
```

`path_relative_to_include()` resolves relative to the calling `root.hcl`'s own directory. Moving
`root.hcl` and every leaf `terragrunt.hcl` together, preserving relative depth, leaves this value —
and the S3 state key — byte-identical. The only valid proof is empirical: `terragrunt state list`
per stack, before and after, diffed line-for-line.

### 2. SOPS upward-search reasoning

`.sops.yaml` resolution walks upward from the encrypted file's own directory. A file at
`platform/foo/secrets.yaml` searches `platform/foo/`, `platform/`, then the true repo root — never
into a sibling `infra/` tree, since that isn't an ancestor. This is why `.sops.yaml` stayed at the
true repo root instead of moving alongside the Terraform tree it also governs.

### 3. `set -e` command-substitution trap — before and after

Before (bug): a failing `git rev-parse` aborts the whole script with exit 128, one line before the
actual safeguard could run.

```bash
set -e
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"   # if this fails, script exits here, silently
if [ ! -f "${REPO_ROOT:-..}/.sops.yaml" ]; then
    echo "refusing to silently skip the update"
    exit 1
fi
```

Reproduction: `bash -c 'set -e; X=$(false); echo after'` never prints `after`; exits 128.

After (fixed, `infra/setup.sh`):

```bash
if ! REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    REPO_ROOT=""
fi
SOPS_YAML_PATH="${REPO_ROOT:-..}/.sops.yaml"

if [ ! -f "$SOPS_YAML_PATH" ]; then
    echo "refusing to silently skip the update"
    exit 1
fi
```

`set -e` does not trigger on a command that is the condition of an `if`, so the fallback branch
runs and the real safeguard below it gets a chance to fire.

### 4. Plaintext secret backup leaks — fixes

```bash
# Backup moved outside the repo, not left as an ungitignored sibling file
BACKUP_DIR="$(mktemp -d)"
mv keys.txt "$BACKUP_DIR/keys.txt.backup"
```

```bash
# sed -i.bak leaves a plaintext .bak; delete it right after the edit succeeds
sed -i.bak "s/YOUR_HCLOUD_TOKEN_HERE/$HCLOUD_TOKEN/" secrets.yaml
rm -f secrets.yaml.bak
```

### 5. `lifecycle { precondition { ... } }` for ambiguous credential/path configs

```hcl
locals {
  using_ssh_auth = var.gitops_repo_ssh_private_key != null && var.gitops_repo_ssh_private_key != ""
}

resource "argocd_repository" "gitops" {
  repo            = var.gitops_repo_url
  ssh_private_key = local.using_ssh_auth ? var.gitops_repo_ssh_private_key : null
  username        = local.using_ssh_auth ? "git" : var.gitops_repo_username
  password        = local.using_ssh_auth ? null : var.gitops_repo_password

  lifecycle {
    precondition {
      condition     = !(local.using_ssh_auth && (var.gitops_repo_username != null || var.gitops_repo_password != null))
      error_message = "Set either gitops_repo_ssh_private_key (SSH auth) or gitops_repo_username/gitops_repo_password (HTTPS auth), not both."
    }
    precondition {
      condition     = (var.gitops_repo_username == null) == (var.gitops_repo_password == null)
      error_message = "gitops_repo_username and gitops_repo_password must both be set or both be null."
    }
    precondition {
      condition     = var.gitops_apps_path != var.gitops_platform_path
      error_message = "gitops_apps_path and gitops_platform_path must not be equal -- an overlapping path would defeat the two-tier trust boundary."
    }
  }
}
```

### 6. `kubernetes_manifest` CRD/CR chicken-and-egg fix

Encountered in this same migration's live deployment, but in the `karpenter` module
(`infra/modules/karpenter/main.tf`), not `argocd-gitops` — flagged here as a general pattern any
`kubernetes_manifest`-based module can hit on a fresh cluster, not something committed as a
scripted step. The fix was an imperative, one-time CLI remediation, not a code change:

```bash
# First pass: create only the CRD-producing resources
terragrunt apply -target='kubernetes_manifest.karpenter_crds' -auto-approve

# Second pass: full apply now succeeds -- the CRDs' schemas exist for the provider to validate against
terragrunt apply -auto-approve
```

## Related

- `docs/solutions/integration-issues/argocd-provider-config-path-tls-cert-verification-failure-2026-07-31.md`
  — different problem (TLS/config_path verification, not repo layout), but touches the same
  `infra/modules/argocd-gitops` / `infra/environments/staging/argocd-gitops/terragrunt.hcl` files.
  Its own path references were already repaired as part of this migration; no further staleness.
- `docs/brainstorms/argocd-gitops-migration-requirements.md` (2026-08-01 amendment) — the origin
  decision document reversing the separate-repo assumption.
- `docs/plans/2026-08-01-001-refactor-monorepo-gitops-layout-plan.md` — the implementation plan.
- `docs/gitops-repo-scaffold.md` — the `apps/`/`platform/` content scaffold this migration
  preserved unchanged, only relocating its target repo.
