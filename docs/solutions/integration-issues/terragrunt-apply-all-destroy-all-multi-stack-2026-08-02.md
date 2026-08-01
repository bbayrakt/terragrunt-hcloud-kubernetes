---
title: Enabling `terragrunt apply --all` / `destroy --all` Across a Multi-Stack Dependency Chain
date: 2026-08-02
category: docs/solutions/integration-issues
module: terragrunt-multi-stack-deployment
problem_type: integration_issue
component: tooling
symptoms:
  - "`terragrunt run-all plan` fails with: unknown command: \"run-all\". Terragrunt no longer forwards unknown commands by default."
  - "`terragrunt plan --all`/`apply --all`/`destroy --all` fail with: resolving dependency \"kubernetes_cluster\" outputs ... detected no outputs. Either the target module has not been applied yet, or the module has no outputs."
  - "The same failure occurs both on a genuinely fresh environment (never applied) and immediately after a full teardown (already destroyed) -- not just one-off"
  - "A `dependency \"X\"` block already has `mock_outputs` configured, yet the error still occurs"
root_cause: config_error
resolution_type: config_change
severity: high
tags: [terragrunt, run-all, dependency-graph, mock-outputs, prevent-destroy, one-command-deploy]
related_components: [argocd-gitops-stack]
---

# Enabling `terragrunt apply --all` / `destroy --all` Across a Multi-Stack Dependency Chain

## Problem

A Terragrunt repo with several chained stacks (`kubernetes-cluster` -> `crds`/`karpenter` ->
`helm-charts` -> `argocd-gitops` -> `gateway-api`, each declaring `dependency`/`dependencies`
blocks) could not be applied or destroyed with a single whole-environment command. Two unrelated
issues combined to block this: a removed CLI command, and an under-scoped `mock_outputs` safety
setting.

## Symptoms

- `terragrunt run-all plan` (and `apply`/`destroy`): `unknown command: "run-all". Terragrunt no
  longer forwards unknown commands by default. Use 'terragrunt run -- run-all ...' or a supported
  shortcut.`
- `terragrunt plan --all` / `apply --all` / `destroy --all` (the modern equivalent): every
  downstream stack fails with `resolving dependency "kubernetes_cluster" outputs: ... detected no
  outputs. Either the target module has not been applied yet, or the module has no outputs.`
- This happened both when standing up a fresh environment from scratch (`kubernetes-cluster` has
  never been applied) and immediately after a full teardown (`kubernetes-cluster` was just
  destroyed) -- i.e. any time the dependency's state is genuinely empty, not a one-off fluke.
- Each affected `dependency "kubernetes_cluster"` block already had a `mock_outputs` entry, which
  did **not** prevent the error.

## What Didn't Work

- Assuming a recent Terragrunt version's `run-all` would still work as a backward-compatible
  alias for the old `apply-all`/`destroy-all`/`plan-all` commands -- it was removed outright, with
  no shim (`terragrunt run-all --help` silently falls through to the generic top-level help
  instead of erroring, which masks the removal until you actually try to run it).
- Assuming `mock_outputs` alone was sufficient -- Terragrunt also gates *which commands* are
  allowed to use a mock via `mock_outputs_allowed_terraform_commands`. The existing config in this
  repo had it scoped to `["init", "validate"]` only (deliberately, from earlier static-validation
  work) -- excluding `plan`/`apply`/`destroy`, the exact commands a whole-environment run needs.

## Solution

**1. Use the modern CLI form.** This Terragrunt version's CLI redesign replaced `run-all <cmd>`
with either `run --all <cmd>` or the shorter per-command form:

```bash
# Old (removed, no shim):
terragrunt run-all apply
terragrunt run-all destroy

# New (either form works identically):
terragrunt run --all apply
terragrunt apply --all
```

**2. Extend `mock_outputs_allowed_terraform_commands` to cover `plan`/`apply`/`destroy`**, not just
`init`/`validate`:

```hcl
dependency "kubernetes_cluster" {
  config_path = "../kubernetes-cluster"

  # Mock is only ever used when the dependency's real output is genuinely unavailable (fresh
  # environment, or already destroyed) -- Terragrunt always prefers the real output over this
  # mock whenever the dependency's state actually exists, so this has no effect on a live,
  # already-applied cluster.
  mock_outputs = {
    kubeconfig_path = local.fallback_kubeconfig_path
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "apply", "destroy"]
}
```

**3. Make sure every stack in the chain actually declares the dependency/ordering edges.** One
stack (`production/gateway-api`) had a bare `dependency "kubernetes_cluster" {}` block with no
`mock_outputs` and no `dependencies { paths = [...] }` ordering block at all -- unlike its staging
counterpart. `--all` commands can only compute a correct DAG from what's actually declared; an
under-declared stack either runs in the wrong order or fails the same "detected no outputs" way.

## Why This Works

Terragrunt's `--all` commands do an upfront pass to resolve every unit's configuration and build
the execution DAG *before* running anything for real. If a `dependency` block's real output is
unavailable at that point (state genuinely empty), Terragrunt needs `mock_outputs` just to get
past that upfront resolution pass -- not to actually use fake data at execution time. By the time
a downstream unit's *own* turn to run comes up in a correctly-ordered `--all` sequence, its
upstream dependency has already really applied (or, for destroy, hasn't been destroyed yet), so
the real output is what actually gets used. The mock is a bootstrapping/idempotency mechanism, not
a live data substitute -- restricting it to `init`/`validate` (reasonable for pure static
validation) accidentally blocked the exact commands that need it to make whole-environment runs
possible at all.

## Prevention

- If a repo wants `apply --all`/`destroy --all`/`plan --all` to work reliably, every
  `dependency "X"` block whose stack might legitimately have empty state (fresh environment, or a
  destroy-then-reapply cycle) needs `mock_outputs` covering every output attribute the file
  actually references (grep for `dependency.<name>.outputs.` to find them all), with
  `mock_outputs_allowed_terraform_commands` including `plan`/`apply`/`destroy` -- not just
  `init`/`validate`.
- Check `dependencies { paths = [...] }` (pure ordering, no outputs) and
  `dependency "X" { config_path = ... }` (outputs) are both present and complete on *every* stack
  in the chain, not just the ones you remember to check -- diff sibling environments'
  `terragrunt.hcl` files against each other (e.g. `staging/gateway-api` vs
  `production/gateway-api`) to catch one that's missing an edge the others have.
- Separately, consider whether any resource needs a `lifecycle { prevent_destroy = true }` guard.
  `prevent_destroy` blocks *any* destroy of that resource, including an intentional
  `destroy --all` -- Terraform has no "except during a real teardown" carve-out. If a repo wants a
  genuine one-command full teardown, `prevent_destroy` and that goal are mutually exclusive; pick
  one deliberately rather than discovering the conflict mid-teardown. (This repo chose to drop
  `prevent_destroy` entirely in favor of one-command teardown, accepting that a normal `apply`
  which happens to plan-destroy a guarded resource now does so silently instead of erroring
  loudly -- review `plan`/`plan --all` output before applying for exactly this reason.)
- After a real `destroy --all`, also clean up local artifacts the modules don't remove themselves
  (e.g. a locally-written kubeconfig/talosconfig file) -- a stale one won't corrupt state, but it
  will produce a confusing connection-timeout error on the next `plan`/`apply`, instead of the
  clear "apply the cluster first" message you'd get with no file at all.

## Related

- `docs/solutions/architecture-patterns/argocd-two-tier-rbac-boundary-and-arc-onboarding-2026-08-02.md`
  -- another ArgoCD/Terragrunt learning from the same migration effort, unrelated root cause
- `AGENTS.md`'s Deployment workflow section -- documents the resulting one-command flow for
  day-to-day use
