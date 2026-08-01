---
title: ArgoCD-Managed GitOps Migration for Staging Runner Charts
type: feat
status: completed
date: 2026-07-30
origin: docs/brainstorms/argocd-gitops-migration-requirements.md
deepened: 2026-07-30
completed: 2026-08-02
---

# ArgoCD-Managed GitOps Migration for Staging Runner Charts

## Overview

Stand up a Terraform-managed ArgoCD control-plane layer (via the `argoproj-labs/argocd` provider) on top of the existing Terragrunt-managed cluster, then migrate `gha-runner-scale-set-controller` and `gha-runner-scale-set` off Terraform `helm_release` and onto ArgoCD-managed delivery from a new, dedicated GitOps repository. Two `AppProject`/`ApplicationSet` trust tiers (`apps`, `platform`) enforce which apps may create cluster-scoped resources. Secrets are split by tier: SOPS+AGE+KSOPS for `platform`, Sealed Secrets for `apps`.

**Repo scope note:** most of this plan modifies `hetznerk8s` (this repo). A handful of units (marked **Target: GitOps repo**) author content for the new, separate, not-yet-created GitOps repository instead — paths in those units are relative to that repo's root, not this one.

---

## Problem Frame

Today, staging installs four Helm charts identically through the shared `helm_charts` map — `argocd`, `external-dns`, `gha-runner-scale-set-controller`, and `gha-runner-scale-set` — as Terraform `helm_release` resources in `modules/helm-charts`, driven by `environments/staging/env.hcl`. (`karpenter` also stays Terraform-managed but through its own dedicated stack, not this shared map.) Everything through this map goes through Terragrunt regardless of whether it's a genuine bootstrap dependency or an ordinary workload. `argocd`, `external-dns`, and `karpenter` stay Terraform-managed (bootstrap exceptions); `gha-runner-scale-set-controller` and `gha-runner-scale-set` move to ArgoCD. The resource-kind axis of that move gets a real enforced boundary — not convention — via `AppProject` whitelisting/blacklisting; the secrets-decrypt axis, by contrast, currently relies on an accepted, documented operational assumption rather than a technical control (see Key Technical Decisions #9). (See origin: docs/brainstorms/argocd-gitops-migration-requirements.md)

---

## Requirements Trace

**Terraform-managed ArgoCD bootstrap layer**
- R1. `argocd`, `external-dns`, `karpenter` remain Terraform-managed; no other chart is added to `helm_charts` going forward.
- R2. New Terragrunt stack authenticates to ArgoCD via port-forward + initial-admin credential (no `gateway-api`/DNS/TLS dependency).
- R3. That stack manages only `argocd_project` x2, `argocd_application_set` x2, and `argocd_repository` x1 — no per-app `argocd_application` resources.

**Trust-tier boundary (AppProjects)**
- R4. The `apps` `AppProject` blocks cluster-scoped resource creation and restricts destinations to a namespace allow-list.
- R5. The `platform` `AppProject` whitelists only the specific cluster-scoped kinds needed.
- R6. Each `AppProject` is backed by its own git-directory-generator `ApplicationSet` (`apps/*`, `platform/*`).
- R16. `apps`-tier destination namespaces get Pod Security Standard enforcement (`pod-security.kubernetes.io/enforce`), closing a boundary gap the resource-kind-only enforcement in R4 leaves open (added during deepening — see Key Technical Decisions #12).

**Chart migration**
- R7. `gha-runner-scale-set-controller` → `platform` tier (installs CRDs).
- R8. `gha-runner-scale-set` → `apps` tier.
- R9. Both charts' values move to the GitOps repo. For `gha-runner-scale-set-controller` specifically (the chart that installs CRDs), ArgoCD/Helm takes over CRD ownership going forward; `gha-runner-scale-set` has no CRDs of its own.

**GitOps repository conventions**
- R10. New, separate, dedicated GitOps repo, `apps/` + `platform/` top-level layout.
- R11. GitOps repo registered via `argocd_repository`, credential sourced from this repo's `secrets.yaml`.

**Secrets management**
- R12. `platform`-tier secrets: SOPS + dedicated AGE key, decrypted via KSOPS patched into the existing `argocd` Helm release.
- R13. Platform AGE private key delivered as a Terraform-created Secret into `argocd-repo-server`; public key in the GitOps repo's `.sops.yaml`.
- R14. `apps`-tier secrets: Sealed Secrets, controller deployed as a `platform`-tier ArgoCD app.

**Environment scope**
- R15. Staging only.

**Origin flows:** F1 (add an `apps`-tier app), F2 (add a `platform`-tier app), F3 (migrate the two existing runner charts — **sequencing revised below**, see Key Technical Decisions #6).

---

## Scope Boundaries

- Production is out of scope (unaffected `helm_charts`/`helm_secrets` gap, deferred separately).
- `argocd`, `external-dns`, `karpenter` are not moved to ArgoCD-managed delivery.
- The GitOps repository itself is not created by this plan — the user creates it separately. This plan defines its required conventions and provides the exact content for its first two apps.
- No changes to the `crds` Terraform stack's mechanism for charts that remain Terraform-managed.
- External Secrets Operator / OpenBao / Vault are not introduced.
- A dedicated, least-privilege ArgoCD local account + token for Terraform's day-2 auth (instead of the bootstrap admin account) is **not** implemented in this plan — see Key Technical Decisions #8 and Risks.

### Deferred to Follow-Up Work

- Replacing Terraform's admin-credential port-forward auth with a scoped `terraform` ArgoCD local account + `argocd_account_token` (Key Technical Decisions #8).
- A technical control preventing `apps/*` manifests from using KSOPS (or exec-plugin capability generally) with the `platform` AGE key (Key Technical Decisions #9) — currently a documented, accepted risk.
- A rotation cadence for the platform AGE key pair and the GitOps repo deploy key (currently unscoped, see Risks & Dependencies).
- Digest pinning (vs. mutable semver tags) for `platform`-tier third-party images (KSOPS init container, OCI runner charts).
- Bringing production's `helm_charts`/`helm_secrets` to parity with this pattern.

---

## Context & Research

### Relevant Code and Patterns

- `environments/staging/{crds,helm-charts,karpenter,gateway-api}/terragrunt.hcl` — identical stack skeleton to mirror for the new stack: `include "root"` / `include "env"`, `locals.fallback_kubeconfig_path`, `terraform { source, before_hook }`, `dependencies`/`dependency "kubernetes_cluster"` with `mock_outputs` (+ `mock_outputs_allowed_terraform_commands = ["init","validate"]`), `generate "providers"`, `inputs`.
- `environments/staging/helm-charts/terragrunt.hcl` and `environments/staging/gateway-api/terragrunt.hcl` — the only two stacks with an `errors { retry ... }` block; a reusable pattern for the new stack if ArgoCD-API-not-ready races appear.
- `modules/helm-charts/main.tf` — generic `secrets`/`charts` map inputs already support everything U5 (platform AGE key delivery) needs: `kubernetes_secret_v1.pre_chart` (namespace-aware, `create_namespace` optional) created before any `helm_release`, and a chart's `values` map is a single Terraform-side `yamlencode(...)`, so new `repoServer.*` keys must be added to the **same** HCL map, not layered on top.
- `modules/crds/main.tf` — `data.helm_template` + `kubernetes_manifest` with `lifecycle { prevent_destroy = true }`, `for_each` sourced from the *same* `helm_charts` map as `modules/helm-charts`. This coupling is the source of the cutover blocker in Key Technical Decisions #5.
- `environments/staging/env.hcl` (`helm_charts.argocd`, lines ~252-287) — exact current values (`global.domain`, `configs.params."server.insecure"=true`, `server.service`, `server.httproute`) that the KSOPS patch must extend additively, not replace.
- `environments/staging/env.hcl` (`helm_charts.gha-runner-scale-set-controller` / `.gha-runner-scale-set`, `helm_secrets.github-arc-pat`) — exact current chart/version/values/secret definitions that the GitOps-repo equivalents must reproduce.
- `root.hcl` / `environments/staging/env.hcl` / `environments/staging/gateway-api/terragrunt.hcl` — `secrets = yamldecode(sops_decrypt_file(...))` pattern; `gateway-api/terragrunt.hcl` shows a stack-level `terragrunt.hcl` is allowed to locally re-decrypt `secrets.yaml` for a secret not already threaded through `env.hcl` — usable for the new stack's GitOps-repo credential if it isn't exposed via `env.hcl`.
- No existing port-forward pattern anywhere in this repo (confirmed by repo-wide search) — the new stack's provider-auth `before_hook` is genuinely new; model it on the existing `before_hook "require_cluster_kubeconfig"`/`"wait_for_gateway_api_crds"` shape (bash script gated on `commands = ["plan","apply","refresh","import"]`).

### Institutional Learnings

- No `docs/solutions/` directory exists in this repo — no prior learnings to draw on. Recommend capturing this migration via the team's `/ce-compound`-equivalent afterward (architecture-pattern: trust-tier `AppProject` boundary; tooling-decision: `argoproj-labs/argocd` + KSOPS + Sealed Secrets split) so future GitOps work here has a first entry.

### External References

- `argoproj-labs/argocd` provider: current released version **v7.15.3**; security fix **GHSA-594f-3595-c47v** landed in v7.15.1; compat matrix places 7.15.x against ArgoCD v3.1-v3.3 (this repo's pinned `argo-cd` chart `9.4.5` → ArgoCD `v3.3.2`, in range). Provider docs: https://registry.terraform.io/providers/argoproj-labs/argocd/latest/docs
- `argo-cd` Helm chart `9.4.5` (`appVersion v3.3.2`) `values.yaml` — confirmed `repoServer.{volumes,initContainers,volumeMounts,env}` and `configs.cm."kustomize.buildOptions"` are the only fields KSOPS needs; `configs.cm.configManagementPlugins.yaml` is dead (removed in ArgoCD 2.8) and must **not** be used.
- KSOPS (`viaduct-ai/kustomize-sops`) current release **v4.5.1**; official Helm-values integration pattern (no raw `kubectl patch`) confirmed via upstream README.
- Sealed Secrets (`bitnami/sealed-secrets`, org-migrated from `bitnami-labs`): chart repo `https://bitnami.github.io/sealed-secrets`, current chart `2.19.1` / controller `v0.38.4`; default scope is `strict` (name+namespace bound). CRD installation: corrected on deepening — ArgoCD's own Helm-source rendering installs a chart's `crds/`-folder CRDs by default (verified against ArgoCD's docs for the pinned `v3.3.2` release); no explicit workaround is expected to be needed (see Key Technical Decisions #7).
- ArgoCD `AppProject` RBAC semantics (verified against `argoproj/argo-cd` source): cluster-scoped resources are **default-deny** (whitelist-only); namespaced resources are **default-allow** unless blacklisted — this is why `Role`/`RoleBinding` need an explicit `namespace_resource_blacklist` on `apps` (Key Technical Decisions #1).
- ApplicationSet Security docs confirm a hard-coded (non-templated) `project` field per `ApplicationSet` — as planned — is the documented-safe pattern against directory-content-driven privilege escalation.
- ArgoCD user-management docs recommend a dedicated scoped local account + token for automation over long-term admin use (Key Technical Decisions #8).

---

## Key Technical Decisions

1. **`apps` `AppProject` gets an explicit `namespace_resource_blacklist` for `{group: rbac.authorization.k8s.io, kind: Role}` and `{..., kind: RoleBinding}`, in addition to the originally-scoped `cluster_resource_blacklist`.** Cluster-scoped resources are already default-deny (leaving `cluster_resource_whitelist` empty is what actually blocks them — the blacklist is defense-in-depth/self-documentation, not the enforcing mechanism). But `Role`/`RoleBinding` are *namespaced* and default-**allow**; without this addition, an `apps`-tier app could create a `RoleBinding` to any pre-existing `ClusterRole` in the cluster and gain elevated rights inside its own namespace — a real privilege-escalation path into a tier meant to be low-trust. This closes the gap the origin doc's R4 intent required but didn't fully specify.
2. **`ApplicationSet` templates use a hard-coded `spec.template.spec.project` (`"apps"` / `"platform"`), never templated from generator output.** Confirmed by upstream ApplicationSet Security docs as the documented-safe pattern — a directory added under `apps/*` cannot land in the `platform` project. Consequence: only Terraform (which owns the two `ApplicationSet` resources) can change tier assignment; ArgoCD RBAC must not grant any non-admin role `applicationsets` write access.
3. **Generated `Application` names are tier-prefixed** (`apps-{{path.basename}}`, `platform-{{path.basename}}`), not raw `{{path.basename}}`. `Application` objects share one namespace; without a prefix, a future `apps/foo` and `platform/foo` would collide. The two charts migrated in this plan don't collide today, but the convention must exist before any second app is added.
4. **`ApplicationSet` templates set `syncPolicy.automated = { prune: true, selfHeal: true }`.** The origin doc's Success Criteria promises "commit → app appears, no manual CLI steps" — that promise is false without automated sync. Not stated explicitly in R1-R15; resolved here as the only sync policy consistent with the stated success criterion. Note: with the default git-generator poll interval (~3 min, `requeue_after_seconds`), "appears" means within that window, not instantly — a webhook would remove the delay but requires ArgoCD reachable from the GitOps host, reintroducing the `gateway-api`/DNS dependency R2 deliberately avoided. Polling is the correct trade-off given R2.
5. **The `crds` Terraform stack's `prevent_destroy`-protected CRD resources for `gha-runner-scale-set-controller` must be disowned from Terraform state — not deleted — before that chart is removed from `helm_charts`.** `modules/crds`'s `for_each` reads the *same* `helm_charts` map as `modules/helm-charts`; removing the chart entry removes it from both maps simultaneously, so Terraform would plan to *destroy* the `kubernetes_manifest.chart_crds` entries for that chart's CRDs — which carry `lifecycle { prevent_destroy = true }` and would abort the apply. The correct sequencing (Unit U7) is: disown those specific resources from Terraform state (they stay in the cluster, untouched) as an explicit step *before* editing `env.hcl`, handing CRD ownership to ArgoCD/Helm per R9 — not something the origin doc anticipated, since R9 assumed simple removal from the map.
6. **F3's cutover order is revised again on deepening: disown (not destroy) the old Terraform-managed `helm_release` from state, mirroring the CRD-disowning technique in decision #5, so ArgoCD adopts the live resources in place, expected to eliminate the downtime window.** The origin doc's F3 sequenced "author in GitOps repo → then remove from `env.hcl`," which risks a live ownership collision. An earlier pass of this plan proposed destroying the old release first to avoid that collision, accepting brief downtime — but a deeper look found neither Kustomize-rendered nor ArgoCD-native Helm sources ever perform a real `helm install`/`upgrade` (ArgoCD's Helm rendering is `helm template` + `kubectl apply`, the same as Kustomize's); no second Helm release object is ever created, so there is nothing for the old release to collide with once Terraform simply stops *tracking* it. Removing the `helm_release` resource from Terraform state (leaving its rendered objects untouched — including the now-orphaned `sh.helm.release.v1.*` release Secret, which is harmless) is intended to let the new `Application`'s first sync patch the same live objects in place and add ArgoCD's own tracking labels — a standard, documented pattern for migrating a Helm-CLI-or-Terraform-managed app into ArgoCD. **This claim is not yet independently verified against this repo's actual charts** — U6's Verification block requires confirming clean adoption (no unnecessary Pod recreation) with a scratch resource before relying on it for the real cutover; if adoption turns out messier than expected, the fallback is the original destroy-then-recreate sequencing with its accepted brief downtime.
7. **Sealed Secrets' CRD is expected to install by default via ArgoCD's own Helm-source handling, not left unhandled.** An earlier pass of this plan assumed `helm template` (which ArgoCD's Helm source uses) never renders a chart's `crds/` folder, and specified a `ServerSideApply=true` sync-option workaround to compensate. Deepening research corrected this against ArgoCD's own current documentation (verified against the `release-3.3` branch, matching this repo's pinned ArgoCD `v3.3.2`): *"Helm installs custom resource definitions in the `crds` folder by default if they are not existing... it is possible to skip the CRD installation step with the `helm-skip-crds` flag."* ArgoCD's Helm-source rendering already handles `crds/` by default; no `ServerSideApply` workaround should be needed for this to work at all. U5's smoke test (Sealed Secrets' `Application` syncing Synced+Healthy with the `SealedSecret` CRD queryable) is the actual verification; only add `ServerSideApply=true` if that test reveals a real problem (e.g. an oversized CRD manifest hitting `kubectl apply`'s annotation size limit — a different, narrower issue than "the CRD never gets created").
8. **Terraform's initial `argocd` provider auth stays on the bootstrap admin account (as originally decided, R2) for this plan; a dedicated least-privilege `terraform` local account + `argocd_account_token` is explicitly deferred**, not implemented now. Upstream docs recommend the scoped-account pattern for long-term automation, and the provider supports it (`argocd_account_token` resource, `accounts.terraform: apiKey` in `argocd-cm`), but wiring a two-phase bootstrap (admin once → create scoped account/token → reconfigure the provider to use it) adds real complexity beyond what R2 decided, and isn't required for this plan's actual apply operations to succeed. Recorded as a Risk and a `Deferred to Follow-Up Work` item so it isn't silently lost.
9. **The KSOPS/apps-tier secret-exfiltration gap (a shared `argocd-repo-server` holds the `platform` AGE private key, so nothing *technically* stops an `apps/*` manifest from decrypting with that key) is accepted as a documented risk, not fixed in this plan.** For a solo-operator repo where the only person with `apps/*` write access already has cluster-admin equivalent access anyway, the practical exposure is low. The same shared-repo-server design also means `--enable-exec` (required for KSOPS, see U4) is a repo-server-wide capability, not scoped to KSOPS's own invocation — in principle any git path the repo-server renders could carry an exec-based Kustomize generator, a strictly larger blast radius than the decrypt-key-mixing risk alone. Both are accepted under the same solo-operator premise; if collaborators with `apps/*`-only access are ever added, this needs a technical control (e.g., a pre-sync policy check rejecting KSOPS annotations or exec-plugin usage outside `platform/*`) before that happens.
10. **Per-app-directory format is *not* uniform `kustomization.yaml` (revised on deepening) — Helm-chart-based apps use ArgoCD's native multi-source `source.chart`/`source.helm` support directly; Kustomize (and KSOPS) is reserved for apps that ship plain manifests or need SOPS-encrypted secrets.** An earlier pass of this plan proposed wrapping every app, including both OCI-sourced runner charts, in a `kustomization.yaml` using Kustomize's `helmCharts:` field, for template uniformity. Research found this is a real risk specifically for OCI charts (`oci://ghcr.io/...`, both migrated charts' registry type): Kustomize's Helm inflator resets `HELM_CONFIG_HOME` on every invocation, discarding OCI registry auth state — the root cause of multiple still-open `argoproj/argo-cd` bugs for exactly this combination (including one left open as of this research); upstream Kustomize documentation itself advises against inflating remote charts in production. ArgoCD's native Helm source (`source.chart` + `source.repoURL` + `source.helm.values`/`valuesObject`, no Kustomize involved, no extra build flags) is a documented, stable, first-party path for OCI charts that avoids this risk surface entirely. Neither of this cutover's two apps currently needs a SOPS-encrypted secret (the controller takes no custom values today; the scale-set's GitHub token becomes a Sealed Secret, which needs no decryption step at sync time), so U4's KSOPS infrastructure is deliberately built ahead of need now — while the argocd-repo-server is already being touched for this migration anyway — rather than as a second, separate change whenever the first genuinely secret-bearing `platform`-tier app arrives; the trade-off (accepting U4's cluster-wide blast radius, see System-Wide Impact) is judged worthwhile to avoid re-opening this same surface twice. The exact per-directory templating mechanism for varying `source.chart`/`source.repoURL` under one shared `ApplicationSet` template is left to implementation (see Open Questions).
11. **`github-arc-pat` is re-homed as a `SealedSecret` authored in `apps/gha-runner-scale-set/`, and the `arc-runners` namespace's ownership moves from Terraform to the `gha-runner-scale-set` Application's `CreateNamespace=true` sync option.** Terraform's `helm_secrets.github-arc-pat` entry and its associated `kubernetes_namespace_v1.pre_created` are removed together with the chart, so nothing is left half-owned.
12. **`apps`-tier destination namespaces get `pod-security.kubernetes.io/enforce` labeling via the `apps` `AppProject`'s `managed_namespace_metadata` field.** The resource-kind-based boundary (decisions #1, #9) only inspects *what kind* of object an `apps`-tier app creates — it has no view into a namespaced `Deployment`/`Pod`'s own spec, so nothing stops an `apps`-tier app from requesting `privileged: true`, a `hostPath` mount, or `hostNetwork`/`hostPID`, which is a node-level escalation path at least as serious as the cluster-scoped-resource risk the whole tier design exists to prevent. `managed_namespace_metadata` is a field ArgoCD's own `AppProject` already supports for exactly this purpose (labeling namespaces it manages via `CreateNamespace=true`) — a cheap, standard addition that closes a gap the plan's own "real enforced boundary" claim would otherwise leave open.

---

## Alternative Approaches Considered

- **Kustomize `helmCharts:` inflation for all apps (uniform format)**: rejected after deepening research surfaced multiple still-open `argoproj/argo-cd` bugs specifically for OCI-registry charts combined with Kustomize's Helm generator, plus upstream Kustomize guidance against inflating remote charts in production. ArgoCD's native multi-source Helm support achieves the same "chart + values" authoring ergonomics without that risk surface (Key Technical Decisions #10).
- **Destroy-then-recreate cutover sequencing**: an earlier pass of this plan proposed destroying the old Terraform-managed `helm_release` before authoring the new GitOps-repo app, accepting brief downtime to avoid an ownership collision. Rejected in favor of state-disown-and-adopt-in-place once research confirmed neither Kustomize- nor ArgoCD-native Helm rendering ever creates a competing Helm release object — there was nothing to collide with, so the downtime wasn't actually required (Key Technical Decisions #6).
- **Scoped `terraform` ArgoCD local account from day one** (vs. the bootstrap admin account): the provider and ArgoCD both support this cleanly (`argocd_account_token`, `accounts.terraform: apiKey`), and it's the documented long-term-correct pattern, but wiring the two-phase bootstrap (admin once → create scoped account/token → reconfigure provider) is real added complexity beyond what R2 decided. Deferred to follow-up hardening rather than built into this plan's first version (Key Technical Decisions #8).

---

## Open Questions

### Resolved During Planning

- `apps` `AppProject` privilege-escalation gap (namespaced `Role`/`RoleBinding` binding to an existing `ClusterRole`): resolved via an explicit `namespace_resource_blacklist` (Key Technical Decisions #1).
- Cross-tier `Application`-name collisions: resolved via tier-prefixed naming, `apps-{{path.basename}}` / `platform-{{path.basename}}` (Key Technical Decisions #3).
- Sync policy for "commit → app appears, no manual sync": resolved as `automated: { prune: true, selfHeal: true }` on both `ApplicationSet` templates (Key Technical Decisions #4).
- `prevent_destroy`-protected CRD resources blocking the cutover apply: resolved via Terraform-state disowning before editing `env.hcl` (Key Technical Decisions #5, Unit U6).
- Helm-release/Application ownership collision during cutover: resolved via state-disown-and-adopt-in-place instead of destroy-then-recreate, eliminating the downtime window (Key Technical Decisions #6).
- Pod Security gap in the `apps`-tier boundary (a namespaced `Deployment`/`Pod` could still request `privileged`/`hostPath`/`hostNetwork`, which resource-kind whitelisting can't prevent): resolved via `pod-security.kubernetes.io/enforce` labeling through the `apps` `AppProject`'s `managed_namespace_metadata` field, traced to a new requirement R16 for explicit scope visibility (Key Technical Decisions #12).
- P0 gap found during deepening: removing `github-arc-pat` from `helm_secrets` would let Terraform *destroy* (not disown) the live `arc-runners` namespace and Secret, since neither carries `prevent_destroy`: resolved by explicitly disowning both from Terraform state alongside the `helm_release`, before the `env.hcl` edit (Unit U7, revised).
- Sealed Secrets' CRD-installation assumption (Key Technical Decisions #7) corrected against ArgoCD's own docs for the pinned `v3.3.2` release: Helm's `crds/` folder installs by default via ArgoCD's Helm-source rendering; the `ServerSideApply=true` workaround is now a conditional fallback, not a required upfront step (Unit U5).
- Terragrunt `before_hook`s cannot feed a fetched credential into Terraform's provider config (side-effect-only, unlike `locals`' `run_cmd()` which would break offline `hcl validate`): resolved via a git-ignored local file + `try(file(...), fallback)`, mirroring this repo's existing `fallback_kubeconfig_path` idiom (Unit U1).
- [Affects R4] Namespace allow-list for `apps`: starts with `arc-runners`, extended as further `apps`-tier apps are added (Unit U2).
- [Affects R5] `platform` cluster-resource whitelist: `CustomResourceDefinition`, `ClusterRole`, `ClusterRoleBinding` — confirmed sufficient for both the migrated controller chart and the Sealed Secrets controller's own template inventory; `platform` destination namespace scope (`arc-systems` + Sealed Secrets' namespace) resolved alongside it (Unit U2).
- [Affects R11] SSH deploy key (not HTTPS token), provisioned read-only, for the `argocd_repository` credential (Unit U3).
- [Affects R12] KSOPS pinned at `v4.5.1`; `configs.cm."kustomize.buildOptions" = "--enable-alpha-plugins --enable-exec"` only — no `--enable-helm` needed, since Helm-chart apps no longer route through Kustomize (Key Technical Decisions #10, Unit U4).
- [Affects R14] Sealed Secrets scope mode: default `strict` (name+namespace-bound) accepted with no override — the safer default, consistent with this migration's per-app, per-namespace secret model; chart pinned at `2.19.1` (Unit U5).
- [Affects R9] `github-arc-pat` re-homed as a `SealedSecret` in `apps/gha-runner-scale-set/`; `arc-runners` namespace ownership transferred to that `Application`'s `CreateNamespace=true` sync option (Key Technical Decisions #11).

### Deferred to Implementation

- [Affects U6, U7][Technical] **Resolved during implementation:** the `argocd_application_set` Terraform resources actually implemented use a single git-path `source` per tier (`source.path = "{{path}}"` against this GitOps repo itself), not a multi-source `source.chart`/`source.repoURL` split. Each Helm-chart-based app directory is instead a thin wrapper chart (`Chart.yaml` with one `dependencies` entry for the real upstream chart + `values.yaml`) so ArgoCD's normal Helm-dependency resolution (`helm dependency build`) handles the rest — no per-directory Terraform templating needed at all. See `docs/gitops-repo-scaffold.md` for the exact file contents.
- [Affects U6, U7][Technical] Exact multi-source `Application` shape combining a remote Helm chart source with a GitOps-repo path source for values/`SealedSecret` manifests (ArgoCD's documented "Helm value files from external Git repository" pattern) — confirmed viable during research, exact field wiring left to implementation.
- [Affects U6][Needs research] Whether adopting the already-live (former-Terraform-managed) resources needs an explicit ArgoCD tracking annotation pre-seeded before first sync, or whether default sync handles adoption cleanly out of the box — verify with a non-critical scratch resource first, per Unit U6's Verification block.
- [Affects U6, U7][Technical] Exact rollback runbook content for a failed cutover after CRD/release/namespace/secret state has already been disowned (re-importing into Terraform state and reconstructing the old resources is possible but non-trivial mid-incident). Producing this runbook is now an explicit prerequisite of U6 (added during deepening); its exact step-by-step content is still left to implementation, not designed here.
- [Affects U6, U7][Technical] **Found and corrected by ce-code-review after this plan's Files sections were written:** the `ApplicationSet` template's `destination.namespace = "{{path.basename}}"` means the GitOps repo directory's *basename* is literally the sync destination namespace. This plan's own Unit U6/U7 `Files:` entries (`platform/gha-runner-scale-set-controller/`, `apps/gha-runner-scale-set/`) name directories after the *chart*, not the *namespace* -- following them literally would produce destination namespaces (`gha-runner-scale-set-controller`, `gha-runner-scale-set`) that aren't in either `AppProject`'s allow-list, and every sync would fail. `docs/gitops-repo-scaffold.md` has been corrected to use namespace-named directories (`platform/arc-systems/`, `apps/arc-runners/`) -- treat that file, not this plan's older `Files:` entries, as authoritative for actual directory names when U6/U7 are executed.

---

## Output Structure

New directories in **this repo** (`hetznerk8s`):

    environments/staging/argocd-gitops/
        terragrunt.hcl
    modules/argocd-gitops/
        main.tf
        variables.tf
        outputs.tf
        README.md

Expected top-level layout of the **new, separate GitOps repo** (created by the user, not by this plan — shown for scope clarity only):

    apps/
        gha-runner-scale-set/
            values.yaml
            sealed-secret.yaml
    platform/
        gha-runner-scale-set-controller/
            values.yaml
        sealed-secrets/
            values.yaml
    .sops.yaml

(`values.yaml` files pair with a multi-source `Application` whose primary source is the remote Helm chart itself — see Key Technical Decisions #10. `kustomization.yaml` is reserved for future `platform`-tier apps that need KSOPS-decrypted secrets; neither app above needs one yet.)

---

## Implementation Units

### Phase 1 — Foundation (Terraform-managed ArgoCD control plane)

- [x] U1. **New Terragrunt stack: ArgoCD provider authentication**

**Goal:** Stand up `environments/staging/argocd-gitops` / `modules/argocd-gitops`, authenticated to the live ArgoCD API via port-forward + the auto-generated initial-admin credential, following this repo's existing stack conventions.

**Requirements:** R1, R2

**Dependencies:** None (depends on the existing `helm-charts` stack having already applied `argocd`, at the Terragrunt `dependency` level)

**Files:**
- Create: `environments/staging/argocd-gitops/terragrunt.hcl`
- Create: `modules/argocd-gitops/main.tf`, `modules/argocd-gitops/variables.tf`, `modules/argocd-gitops/outputs.tf`, `modules/argocd-gitops/README.md`
- Modify: `AGENTS.md` (add a validate line for the new stack), `README.md` (deployment-order list + repository-layout tree)

**Approach (credential data-flow mechanism specified on deepening — the before_hook side-effect model alone can't feed a value into Terraform's provider config):**
- Mirror `environments/staging/helm-charts/terragrunt.hcl`'s skeleton: `include "root"`/`include "env"`, `locals.fallback_kubeconfig_path`, `dependency "kubernetes_cluster"` with `mock_outputs`, `dependencies { paths = ["../helm-charts"] }`.
- Add a `before_hook` (new pattern for this repo, scoped to `commands = ["plan","apply","refresh","import"]` — deliberately excluding `validate`/`hcl validate`, matching this repo's existing `before_hook` scoping) that port-forwards `argocd-server` in namespace `argocd`, reads `argocd-initial-admin-secret` via `kubectl`, and **writes the decoded password to a git-ignored local file** in the stack's working directory (Terragrunt `before_hook`s are side-effect-only and cannot return a value into HCL evaluation directly, unlike a `locals` block's `run_cmd()` — which *would* re-evaluate on every parse, including `terragrunt hcl validate`, breaking this repo's static-safe validation convention).
- The generated `provider "argocd"` block reads that file via `try(trimspace(file("${get_terragrunt_dir()}/.argocd-admin-password")), "placeholder-for-validate")`, mirroring this repo's existing `fallback_kubeconfig_path`/`mock_outputs` idiom for keeping `terragrunt hcl validate`/`format` static-safe (per `AGENTS.md`: "use deterministic local fallbacks... so validation remains static-safe") — the real password is only required to resolve at `plan`/`apply` time, after the `before_hook` has run.
- Ensure the `before_hook` script and any Terragrunt/CI output suppress the fetched password from stdout logs (it is full ArgoCD admin, capable of rewriting the very `AppProject`/RBAC definitions this migration establishes — materially higher-privilege than the other secrets already threaded through this repo's `local.secrets.*` pattern); add the local password file to `.gitignore`.
- `generate "providers"` block declares `argocd = { source = "argoproj-labs/argocd", version = "= 7.15.3" }` (exact pin, not `~>`, per Key Technical Decisions research: the provider has shipped breaking changes between minors) plus a `provider "argocd" { port_forward_with_namespace = "argocd"; plain_text = true; username = "admin"; password = ... }`.

**Patterns to follow:**
- `environments/staging/helm-charts/terragrunt.hcl` (stack skeleton, `before_hook` shape, `commands` scoping)
- `environments/staging/crds/terragrunt.hcl` (minimal `dependency`/`generate` shape without an `errors` block, if no retry logic is needed here)
- `locals.fallback_kubeconfig_path` in every existing stack (the `try(..., deterministic_fallback)` idiom this unit's password handling reuses)

**Test scenarios:**
- Happy path: `terragrunt hcl validate` (repo root) and `terragrunt validate` (in the new stack dir) both succeed with no real cluster present and no local password file written yet, using the `try(file(...), "placeholder-for-validate")` fallback.
- Happy path: with a live staging cluster, `terragrunt plan` in the new stack runs the `before_hook`, writes the real password, and succeeds with zero unexpected diffs against a fresh ArgoCD install.
- Error path: if `argocd-server` is not yet reachable (port-forward fails), the `before_hook` fails with a clear error message rather than a confusing provider-auth stack trace.
- Security: confirm the fetched password never appears in `terragrunt`/`terraform` stdout or any CI log output, and that the local password file is git-ignored.

**Verification:**
- New stack directory validates per the AGENTS.md workflow (`terragrunt hcl format` / `hcl validate` / per-module `init -reconfigure && validate`).
- `terraform providers` in the new stack shows `argoproj-labs/argocd` pinned at the intended version.

---

- [x] U2. **`apps` and `platform` `AppProject`s**

**Goal:** Create the two trust-tier `argocd_project` resources with the hardened resource-scoping decided in Key Technical Decisions #1, #12.

**Requirements:** R4, R5, R16

**Dependencies:** U1

**Files:**
- Modify: `modules/argocd-gitops/main.tf` (add `argocd_project.apps`, `argocd_project.platform`)
- Modify: `modules/argocd-gitops/variables.tf` (namespace allow-list input for `apps`, cluster-resource-kind list input for `platform`)

**Approach:**
- `apps`: `cluster_resource_blacklist = [{group:"*", kind:"*"}]` (defense-in-depth/self-documentation), `namespace_resource_blacklist` covering `{rbac.authorization.k8s.io, Role}` and `{..., RoleBinding}`, `destination` block(s) restricted to an explicit namespace allow-list (starting with `arc-runners`, extended as further `apps`-tier apps are added), `managed_namespace_metadata` applying `pod-security.kubernetes.io/enforce: restricted` (or `baseline`, if `restricted` proves too strict for a given app) to namespaces this project creates via `CreateNamespace=true` (Key Technical Decisions #12).
- `platform`: `cluster_resource_whitelist` covering `CustomResourceDefinition`, `ClusterRole`, `ClusterRoleBinding` (confirmed sufficient for both the migrated controller chart and the planned Sealed Secrets controller's own CRD/RBAC needs — extend later only if a future platform app needs more); `destination` block(s) restricted to an explicit namespace allow-list (`arc-systems` for the controller, plus wherever Sealed Secrets lands, e.g. `kube-system` or a dedicated namespace) — deliberately not `*`, matching the origin document's Key Decisions table ("Broader, but still project-scoped") rather than left unrestricted (a gap this unit's own Verification step would otherwise be checking against an undefined value).

**Patterns to follow:**
- `modules/helm-charts/variables.tf` (generic `any`-typed map inputs for extensibility, matching this repo's existing style)

**Test scenarios:**
- Happy path: `terraform plan` shows both `argocd_project` resources created with the intended whitelist/blacklist contents.
- Edge case: a scratch `Application` under `apps` attempting to include a `ClusterRole` in its rendered manifests fails to sync ("resource not permitted in project").
- Edge case: a scratch `Application` under `apps` attempting to include a `RoleBinding` bound to an existing `ClusterRole` fails to sync (validates Key Technical Decisions #1's fix).
- Edge case: a scratch `Application` under `apps` deploying a `Pod`/`Deployment` requesting `privileged: true` is rejected at admission time once the namespace carries the Pod Security label (validates Key Technical Decisions #12's fix).

**Verification:**
- `argocd proj get apps` / `argocd proj get platform` (via the ArgoCD UI or CLI) show the expected whitelist/blacklist and destination configuration.
- `kubectl get ns arc-runners -o jsonpath='{.metadata.labels}'` shows the expected `pod-security.kubernetes.io/enforce` label once that namespace exists.

---

- [x] U3. **`apps`/`platform` `ApplicationSet`s and GitOps `argocd_repository` registration**

**Goal:** Wire the two git-directory-generator `ApplicationSet`s (hard-coded project, tier-prefixed naming, automated sync) and register the new GitOps repo.

**Requirements:** R3, R6, R11

**Dependencies:** U1, U2. **Precondition (carried forward from the origin document's Dependencies/Assumptions):** the GitOps repository must already exist, with a Terraform-readable access credential already added to `secrets.yaml`, before this unit's `terraform apply` is run — `argocd_repository`/`argocd_application_set` resources will fail to apply meaningfully against a nonexistent repo. This is a real execution-order gate, not just a documentation note.

**Files:**
- Modify: `modules/argocd-gitops/main.tf` (add `argocd_application_set.apps`, `argocd_application_set.platform`, `argocd_repository.gitops`)
- Modify: `modules/argocd-gitops/variables.tf` (GitOps repo URL + credential inputs)
- Modify: `secrets.yaml.example` (document the new GitOps repo credential placeholder key)

**Approach:**
- `argocd_repository`: `repo` = the GitOps repo's SSH URL (per Outstanding Question resolution — pick SSH deploy key, since it requires no separate PAT-rotation story and matches this repo's existing single-purpose-credential style); the deploy key should be provisioned **read-only** at the git-hosting-provider level (ArgoCD never needs to write to this repo); credential sourced from a new `secrets.yaml` key, decrypted the same way `local.secrets.*` already works.
- `argocd_application_set.apps`: `generator.git.directory { path = "apps/*" }`; `template.metadata.name = "apps-{{path.basename}}"`; `template.spec.project = "apps"`; `template.spec.syncPolicy.automated = { prune = true, self_heal = true }`; `syncOptions` include a deletion-safety option (ArgoCD's `preserveResourcesOnDeletion` on the `ApplicationSet` spec, or per-resource `Prune=false` sync-option annotations on CRD/CR manifests) so an accidental directory deletion/rename in the GitOps repo doesn't cascade-delete live cluster resources with no Terraform-level backstop left (the `prevent_destroy` safety net was deliberately removed from these charts' CRDs in Key Technical Decisions #5/#6 specifically to hand ownership to ArgoCD — that hand-off should not also mean "one fat-fingered `git rm -r` deletes everything").
- `argocd_application_set.platform`: mirrors the above with `platform/*`, `platform-{{path.basename}}`, `project = "platform"`, same deletion-safety option.

**Patterns to follow:**
- N/A within this repo (new pattern) — follow the `argocd_application_set` schema confirmed during research (`spec.generator.git.directory.path`, `spec.template.spec.project`, `spec.template.spec.syncPolicy`).

**Test scenarios:**
- Happy path: `terraform plan` shows both `ApplicationSet`s and the `argocd_repository` created.
- Happy path: after apply, with an empty GitOps repo (just `.sops.yaml` and empty `apps/`/`platform/` dirs), `kubectl get applications -n argocd` shows zero generated Applications (no directories yet, no false-positive apps).
- Integration: adding a throwaway directory under `apps/` (e.g. a trivial ConfigMap-only Kustomize app) causes a new `Application` named `apps-<dirname>` to appear within one poll interval, Synced+Healthy, without any manual `argocd app sync`.
- Edge case: deleting that throwaway directory does not cascade-delete resources unexpectedly (validates the deletion-safety option above behaves as intended before it's ever relied on for a real app).
- Error path: confirm this unit's `terraform apply` fails clearly (not silently) if attempted before the GitOps repo/credential precondition above is met.

**Verification:**
- `argocd repo list` shows the GitOps repo as connected.
- `argocd appset get apps` / `argocd appset get platform` show the correct generator paths and hard-coded `project`.

---

### Phase 2 — Secrets tooling (both tiers wired before any real app needs them)

- [x] U4. **Platform-tier AGE key + KSOPS patch on the existing `argocd` Helm release**

**Goal:** Deliver a dedicated AGE key pair for `platform`-tier secrets into the cluster, and patch the *existing* Terraform-managed `argo-cd` chart's `repoServer` values so KSOPS can decrypt them — without breaking any current values.

**Requirements:** R12, R13

**Dependencies:** None (independent of U1-U3; only depends on the existing `helm-charts` stack)

**Files:**
- Modify: `environments/staging/env.hcl` — add a new `helm_secrets` entry (platform AGE private key, `namespace = "argocd"`, `create_namespace = false` since the chart already creates it) and extend `helm_charts.argocd.values` additively with `configs.cm."kustomize.buildOptions"` and a new `repoServer` block.
- Modify: `secrets.yaml.example` (document the new platform AGE private-key placeholder key)

**Approach:**
- Generate the platform-tier AGE key pair (outside Terraform, one-time operator action); store the private key text in `secrets.yaml` under a new key, referenced from `env.hcl` the same way `local.secrets.github_token` etc. already are.
- Reuse `modules/helm-charts`'s existing generic `secrets` map mechanism (`kubernetes_secret_v1.pre_chart`) — **no new Terraform code needed**, only a new `env.hcl` entry — to create the Secret holding the private key (e.g. key `keys.txt`) in the `argocd` namespace before `argocd`'s `helm_release` (wave 3) applies, guaranteeing ordering via the module's existing `depends_on` chain.
- Extend `helm_charts.argocd.values` with: `configs.cm."kustomize.buildOptions" = "--enable-alpha-plugins --enable-exec"` (both flags required — `--enable-exec` alone is easy to miss per KSOPS's docs); `repoServer.volumes` (mount the new Secret), `repoServer.initContainers` (`viaductoss/ksops:v4.5.1`, pinned), `repoServer.volumeMounts`, `repoServer.env` (`SOPS_AGE_KEY_FILE`). None of these keys collide with the existing `global.domain`/`configs.params`/`server.*` keys already in that map.

**Patterns to follow:**
- `modules/helm-charts/main.tf`'s existing `secrets`/`kubernetes_secret_v1.pre_chart` mechanism (already used for `cloudflare-api-key`, `github-arc-pat`).

**Test scenarios:**
- Happy path: `terraform plan` on the `helm-charts` stack shows only additive changes to the `argocd` release's values (no unrelated diff to `global.domain`/`server.httproute`/etc.).
- Integration: after apply, `kubectl exec -n argocd deploy/argocd-repo-server -- ksops --version` succeeds and the AGE key file is present at the expected mount path.
- Integration: a scratch SOPS-encrypted test manifest under a throwaway `platform/` directory decrypts correctly when ArgoCD renders it (validates the not-independently-confirmed KSOPS v4.5.1 / ArgoCD v3.3.2 combination flagged in research).
- Error path: if the KSOPS patch is malformed, `argocd-repo-server` fails to start / crash-loops — confirm this is caught by a scratch-`Application` smoke test *before* any real app depends on it (Key Technical Decisions notes this affects the whole ArgoCD instance, not just `platform`).

**Verification:**
- `argocd-repo-server` pod is healthy after the values change.
- A scratch platform-tier app with a SOPS-encrypted Secret syncs and the resulting Kubernetes Secret contains the decrypted value.

---

- [x] U5. **Bootstrap Sealed Secrets as the first `platform`-tier app**

> **Completed (2026-08-02):** Authored `platform/sealed-secrets/` as the thin wrapper chart per
> `docs/gitops-repo-scaffold.md` (superseding this unit's older multi-source `Application`
> description below -- see the Outstanding Questions resolution note). Applied live against
> staging: `platform-sealed-secrets` Synced/Healthy, `kubeseal --fetch-cert` confirmed working,
> sealing keypair backed up (SOPS-encrypted, committed as `infra/environments/staging/backup-
> secrets.yaml`). No `ServerSideApply` override was needed for this chart specifically (only U6's
> CRDs hit that limit).

**Goal:** Deploy the Sealed Secrets controller itself as an ArgoCD-managed `platform`-tier app.

**Requirements:** R14

**Dependencies:** U2, U3 (needs the `platform` `AppProject`/`ApplicationSet` live)

**Files:**
- **Target: GitOps repo** (not yet created) — Create: `platform/sealed-secrets/values.yaml` (values for a multi-source `Application` whose primary source is the `sealed-secrets` chart `2.19.1` from `https://bitnami.github.io/sealed-secrets`, pinned to the `ghcr.io/bitnami/sealed-secrets-controller` image explicitly rather than the chart's registry default per research)

**Approach:**
- Use ArgoCD's native multi-source `Application` (`source.chart`/`source.repoURL`/`source.targetRevision` for the chart itself, a second `ref`-linked git-path source for `values.yaml`) rather than a Kustomize `helmCharts:` wrapper — this chart is a classic HTTPS Helm repo, not OCI, but native Helm source is simpler and consistent with Key Technical Decisions #10 regardless.
- Do **not** add a `ServerSideApply=true` sync-option workaround up front (corrected on deepening — see Key Technical Decisions #7): ArgoCD's own Helm-source rendering installs a chart's `crds/`-folder CRDs by default (confirmed against ArgoCD's docs for the pinned `v3.3.2` release), so the `SealedSecret` CRD is expected to install without any extra sync option. Only add `ServerSideApply=true` if the smoke test below reveals a real problem.
- Confirm `platform`'s `cluster_resource_whitelist` (U2) already covers this chart's needs (`CustomResourceDefinition`, `ClusterRole`, `ClusterRoleBinding` — confirmed sufficient during research from the chart's template inventory; no additional whitelist entry expected).

**Test scenarios:**
- Happy path: the `sealed-secrets` `Application` syncs Synced+Healthy, `kubectl get sealedsecrets.bitnami.com` (CRD) is queryable, and the controller pod is running — with no `ServerSideApply` override needed.
- Error path: if the CRD does *not* install by default (contradicting the corrected Key Technical Decisions #7 assumption), add `ServerSideApply=true` as the fallback and note why in this unit before proceeding.
- Verification-critical: immediately after first successful deploy, back up the controller's auto-generated sealing keypair (Secret in the controller's namespace) — required before any real `apps`-tier `SealedSecret` is committed, per Key Technical Decisions risk on key loss.

**Verification:**
- `kubeseal --fetch-cert` against the live controller succeeds.
- The sealing-key Secret has been backed up out-of-band (documented, not just assumed).

---

### Phase 3 — Cutover (migrate the two motivating charts)

- [x] U6. **Migrate `gha-runner-scale-set-controller` to the `platform` tier**

> **Implementation status:** the Terraform-side work is done — the 4 `prevent_destroy`-protected CRD state entries were disowned (`tofu state rm`, confirmed clean via `tofu state list`), and the chart entry was removed from `helm_charts` in `env.hcl` (the `helm-charts` stack's state for this chart was already empty pre-migration, so there was nothing live to disown there). What remains: authoring the GitOps-repo content (see `docs/gitops-repo-scaffold.md`) and the actual sync/verification steps, both of which require the cluster to exist.

> **Completed (2026-08-02):** Authored `platform/arc-systems/` per `docs/gitops-repo-scaffold.md`.
> Found and fixed two real bugs during live sync, both scoped to the `argocd-gitops` Terraform
> module rather than this unit's own files: (1) neither AppProject whitelisted `Namespace`, so
> `CreateNamespace=true`'s PreSync task failed outright for every platform-tier app -- added
> `{group:"", kind:"Namespace"}` to `platform_cluster_resource_whitelist`; (2) this chart's CRDs
> (`autoscalinglisteners`/`autoscalingrunnersets`/`ephemeralrunners`/`ephemeralrunnersets`) exceed
> Kubernetes' 262144-byte `last-applied-configuration` annotation limit under client-side apply --
> a known upstream actions-runner-controller issue -- so added `ServerSideApply=true` to the
> `platform` `ApplicationSet`'s sync options. Verified live: `platform-arc-systems` Synced/Healthy,
> controller Deployment Running in `arc-systems`, CRDs Established and queryable.

**Goal:** Move this chart off Terraform-managed Helm cleanly, handling the `prevent_destroy` CRD blocker and avoiding a Helm-release/Application ownership collision.

**Requirements:** R7, R9

**Dependencies:** U2, U3, U4 (needs `platform` tier live and KSOPS wired, even though this specific chart needs no secrets today — establishes the pattern). **Prerequisite (added on deepening):** a drafted, dry-run rollback procedure for a failed state-disowning cutover (re-importing the disowned `kubernetes_manifest.chart_crds`/`helm_release` resources back into Terraform state) must exist and be reviewed before this unit's step 1 begins — the plan's own risk assessment names this as one of its two riskiest operational moments (see Risks & Dependencies), and it should not be improvised mid-incident.

**Files:**
- Modify (this repo): `environments/staging/env.hcl` (remove the `gha-runner-scale-set-controller` entry from `helm_charts`)
- **Target: GitOps repo** — Create: `platform/gha-runner-scale-set-controller/values.yaml` (paired with a multi-source `Application`: primary source = `oci://ghcr.io/actions/actions-runner-controller-charts`, chart `gha-runner-scale-set-controller`, version `0.13.1`, namespace `arc-systems`; secondary `ref` source = this git path, for values)

**Approach (revised on deepening — disown-and-adopt, not destroy-and-recreate; see Key Technical Decisions #5, #6, #10):**
1. Disown the `prevent_destroy`-protected `kubernetes_manifest.chart_crds` entries for this chart from Terraform state (cluster objects untouched) — a one-time, explicit operational step, done *before* editing `env.hcl`.
2. Disown the `helm_release.wave_1["gha-runner-scale-set-controller"]` resource from Terraform state (the live Deployment/ServiceAccount/etc. are left running, untouched); remove the chart entry from `helm_charts` in `env.hcl` and apply the `helm-charts` stack — this only drops Terraform's tracking, it does not touch the cluster.
3. Author `platform/gha-runner-scale-set-controller/values.yaml` in the GitOps repo (native multi-source `Application`, not a Kustomize wrapper) — the `platform` `ApplicationSet`'s directory generator picks it up, and ArgoCD's first sync adopts the already-live objects in place (patching in its own tracking labels), with no downtime window.

**Patterns to follow:**
- The exact chart/version/namespace already defined in `environments/staging/env.hcl`'s current `gha-runner-scale-set-controller` block (1:1 reproduction, values unchanged — this chart currently takes no custom values).

**Test scenarios:**
- Happy path: after step 3, the `platform-gha-runner-scale-set-controller` Application is Synced+Healthy and the controller Deployment is Running in `arc-systems`, with no interruption to the controller's availability across the cutover.
- Integration: ArgoCD's first sync patches the already-live Deployment/ServiceAccount/RBAC objects in place (label/annotation updates only) rather than recreating them — confirm no unnecessary Pod restarts or resource recreation occurred.
- Integration: CRDs previously owned by Terraform (`prevent_destroy`) are now owned by the Helm release ArgoCD manages, confirmed via `kubectl get crd <name> -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-name}'` matching the new ArgoCD-managed release.
- Error path / gate: before authoring the GitOps-repo content (step 3), confirm the disowned resources (CRDs and the old release's objects) are healthy and no longer tracked in either the `crds` or `helm-charts` Terraform state — this is the explicit checkpoint the origin doc's F3 was missing.

**Verification:**
- `env.hcl`'s `helm_charts` no longer contains `gha-runner-scale-set-controller`; `terraform state list` in the `crds` stack no longer contains its CRD resources.
- `argocd app get platform-gha-runner-scale-set-controller` reports Synced/Healthy.

---

- [x] U7. **Migrate `gha-runner-scale-set` off Terraform, re-homing `github-arc-pat`** (re-homed to `platform/arc-runners/`, not `apps/` -- see the 2026-08-02 correction note below)

> **Implementation status:** `env.hcl` changes are done (`gha-runner-scale-set` removed from `helm_charts`, `github-arc-pat` removed from `helm_secrets`) — no state disowning was needed since the `helm-charts` stack's state was already empty for this chart/secret/namespace pre-migration. What remains: authoring the GitOps-repo content (`docs/gitops-repo-scaffold.md`), sealing the real `github_token` with `kubeseal` once the Sealed Secrets controller is live, and sync/verification against the real cluster.

> **Completed, then corrected (2026-08-02):** First pass authored `apps/arc-runners/` per
> `docs/gitops-repo-scaffold.md`, using the real `githubConfigUrl` already in `infra/secrets.yaml`
> and a `SealedSecret` generated by piping the real `github_token` from `sops -d` through
> `kubectl --dry-run=client` through `kubeseal`, never touching disk in plaintext. Found two real
> issues during live sync: (1) the chart's Helm `lookup()` auto-discovers the controller's
> ServiceAccount only within its own release namespace, never finding it in `arc-systems` -- set
> `controllerServiceAccount.name`/`.namespace` explicitly in `values.yaml`; (2) the chart
> unconditionally creates its own namespace-scoped manager `Role`+`RoleBinding` (granting the
> `arc-systems` controller's ServiceAccount cross-namespace access), which the `apps` AppProject's
> `Role`/`RoleBinding` blacklist (R4's anti-escalation design) correctly blocked.
>
> **The first fix attempt was wrong and was reverted the same session:** removing the `apps`
> blacklist to unblock this was proposed and initially applied, framed as an accepted solo-operator
> risk. The user corrected this: `apps/` is designed from the start as the tier ordinary cluster
> *users* (not cluster admins) will eventually push to, and an RBAC-escalation path is never an
> acceptable risk there, not even temporarily -- R8's original assumption that this chart "only
> creates namespaced custom-resource instances" is simply wrong. **Correct fix:** moved the whole
> chart to `platform/arc-runners/` instead (`git mv`), added `arc-runners` to
> `platform_destination_namespaces`, removed it from (now-empty) `apps_destination_namespaces`,
> restored the `apps` AppProject's `Role`/`RoleBinding` blacklist and its `restricted` PSA default.
> `pod-security.kubernetes.io/enforce` doesn't apply to `platform`-tier namespaces at all (no
> `managed_namespace_metadata` there), so the runner Pod's need for elevated Pod capabilities is
> moot in its new home -- no PSA downgrade needed or applied. Cleaned up orphaned resources left by
> the tier move (old `apps-arc-runners`-named `AutoscalingRunnerSet` -- deleting it triggered proper
> GitHub scale-set deregistration via its finalizer -- plus its owned Role/RoleBinding/ServiceAccount
> and a dangling PSA label on the shared `arc-runners` namespace). Verified live:
> `platform-arc-runners` Synced/Healthy, runner Pod Running and logging "Connected to GitHub" /
> "Listening for Jobs", no `apps-arc-runners` Application or orphaned objects remaining. See
> `docs/brainstorms/argocd-gitops-migration-requirements.md`'s Key Decisions for the corrected
> architectural rule this establishes: **any app needing RBAC-object (`Role`/`RoleBinding`) or
> cluster-scoped creation rights belongs in `platform/`, full stop -- never accepted as a risk
> exception in `apps/`.**

**Goal:** Move this chart to the `apps` tier, replacing its Terraform-created secret with a `SealedSecret` and handing off `arc-runners` namespace ownership.

**Requirements:** R8, R9, R14

**Dependencies:** U2, U3, U5, U6 (the controller must already be running in `platform` before the scale-set can register runners)

**Files:**
- Modify (this repo): `environments/staging/env.hcl` (remove `gha-runner-scale-set` from `helm_charts`, remove `github-arc-pat` from `helm_secrets`)
- **Target: GitOps repo** — Create: `apps/gha-runner-scale-set/values.yaml` (paired with a multi-source `Application`: primary source = `oci://ghcr.io/actions/actions-runner-controller-charts`, chart `gha-runner-scale-set`, version `0.13.1`, namespace `arc-runners`; secondary `ref` source = this git path, values matching the current `githubConfigUrl`/`runnerGroup`/`minRunners`/`githubConfigSecret` block), `apps/gha-runner-scale-set/sealed-secret.yaml` (a `SealedSecret` producing the `github-arc-pat` Secret with key `github_token`, applied as a plain manifest alongside the values file via the same git-path source — no Kustomize wrapper needed)

**Approach (revised on deepening — disown-and-adopt, not destroy-and-recreate; see Key Technical Decisions #5, #6, #10; corrected to fix a P0 gap found during deepening — see below):**

> **Correction (P0, found during deepening):** an earlier pass of this unit only disowned the `helm_release` and assumed the namespace/secret were "left running, untouched." That's wrong. `modules/helm-charts/main.tf`'s `kubernetes_namespace_v1.pre_created` (keyed by `local.secret_namespaces`, derived from the `helm_secrets` map) and `kubernetes_secret_v1.pre_chart` (the `github-arc-pat` Secret itself) are **both** ordinary Terraform-managed resources with **no `prevent_destroy`** — unlike the CRDs in `modules/crds`. Simply removing the `github-arc-pat` entry from `helm_secrets` (as this unit originally described) would make Terraform plan to **destroy** both the `arc-runners` namespace and the `github-arc-pat` Secret, cascade-deleting every live object in that namespace — exactly the outage this unit's disown-and-adopt design exists to prevent, just via a resource this unit forgot to disown. Both must be explicitly disowned, not just the `helm_release`.

1. Disown `kubernetes_namespace_v1.pre_created["arc-runners"]` **and** `kubernetes_secret_v1.pre_chart["github-arc-pat"]` from Terraform state (both left live, untouched), *and* disown the `helm_release.wave_2["gha-runner-scale-set"]` resource (this chart has no `manage_crds`-protected CRDs of its own, so no CRD-disowning step is needed here, unlike U6). Remove `gha-runner-scale-set` from `helm_charts` and `github-arc-pat` from `helm_secrets` in `env.hcl`, then apply the `helm-charts` stack — this only drops Terraform's tracking of all three resources; nothing is destroyed, so the running Deployment/RBAC/namespace/Secret are all still live and correct.
2. `kubeseal`-encrypt the current `github_token` value against the now-running Sealed Secrets controller (U5), producing `sealed-secret.yaml`. Because the live `github-arc-pat` Secret was disowned (not destroyed) in step 1, there is no window where `arc-runners` lacks a valid secret — the SealedSecret's decrypted output targets the same Secret name and simply gets adopted/patched by ArgoCD's first sync in step 3, the same continuity guarantee as the namespace and Deployment.
3. Author `apps/gha-runner-scale-set/values.yaml` + `sealed-secret.yaml` in the GitOps repo — the `apps` `ApplicationSet`'s directory generator picks it up, and ArgoCD's first sync adopts the already-live namespace, Deployment, RBAC, and Secret in place, with `CreateNamespace=true` so `arc-runners` gets a clear, single owner going forward.

As a broader defense-in-depth improvement (optional, not required for this cutover to succeed): consider adding `lifecycle { prevent_destroy = true }` to `kubernetes_namespace_v1.pre_created` in `modules/helm-charts/main.tf`, matching the safety net `modules/crds` already gives CRDs, so a future map-key removal aborts loudly instead of silently destroying a live namespace for *any* secret-backed namespace, not just this one.

**Patterns to follow:**
- The exact chart/version/values already defined in `environments/staging/env.hcl`'s current `gha-runner-scale-set` block.
- U6's CRD-disowning step (the same `terraform state rm`-style technique, applied here to the namespace and secret resources instead).

**Test scenarios:**
- Happy path: `apps-gha-runner-scale-set` Application is Synced+Healthy, with no interruption to runner availability across the cutover; a real GitHub Actions job picks up a runner from the scale set, confirming the re-sealed token round-trips correctly.
- Edge case: `arc-runners` namespace and the `github-arc-pat` Secret both exist with exactly one owner (ArgoCD) after cutover — confirmed via `terraform state list` no longer containing either resource in the `helm-charts` stack.
- Edge case: `pod-security.kubernetes.io/enforce` labeling (Key Technical Decisions #12) on `arc-runners` doesn't block the real `gha-runner-scale-set` chart's actual pod spec — unlike U2's synthetic scratch-Pod test, this validates the control against the real migrated workload; if the runner pods need capabilities the chosen PSA level blocks, downgrade the label from `restricted` to `baseline` for this namespace rather than discovering the failure only during a live cutover.
- Error path: if the `SealedSecret` fails to decrypt (wrong scope/controller), the `Application` reports a clear sync error rather than silently running with a missing secret.
- Error path (critical, corrects the P0 gap): before removing `github-arc-pat` from `helm_secrets`, confirm the plan against `helm-charts` shows the namespace and secret as **state removal**, not **destroy** — a `terraform plan` showing a `-` (destroy) action on either resource is a hard stop.
- Integration: ArgoCD's first sync patches the already-live objects in place rather than recreating them — confirm no unnecessary Pod restarts or resource recreation occurred (mirrors U6's equivalent check).

**Verification:**
- `argocd app get apps-gha-runner-scale-set` reports Synced/Healthy.
- `env.hcl`'s `helm_charts` and `helm_secrets` no longer reference this chart or `github-arc-pat`.
- End-to-end: a test workflow run in the GitHub repo configured against this runner group completes successfully.

---

## System-Wide Impact

- **Interaction graph:** New Terragrunt dependency edge: `argocd-gitops` stack depends on `helm-charts` (needs the live `argocd` release + its initial-admin secret). `crds` and `helm-charts` remain coupled via the shared `helm_charts` map for all *remaining* Terraform-managed charts — unaffected by this plan except for the one-time CRD-state-disowning step in U6.
- **Error propagation:** A bad KSOPS patch (U4) affects the *entire* ArgoCD instance's manifest rendering (one shared `argocd-repo-server`), not just `platform`-tier apps — smoke-test before relying on it.
- **State lifecycle risks:** The `prevent_destroy` CRD-state disowning and the helm-release state disowning (both U6, U7) are the two riskiest operational moments in this plan; both now have explicit checkpoints (see Verification blocks) that the origin doc's F3 lacked, and both use disown-and-adopt rather than destroy-and-recreate to eliminate the downtime window (Key Technical Decisions #6).
- **API surface parity:** Production is untouched; no parity work is implied or required by this plan.
- **Integration coverage:** Confirming ArgoCD's first sync adopts the already-live, now-disowned resources in place — rather than recreating them — (U6/U7) can only be verified by observing live cluster state, not by `terraform plan` alone.
- **Unchanged invariants:** `argocd`, `external-dns`, `karpenter` bootstrap chain and ordering; the `crds` stack's mechanism for any chart still in `helm_charts`; production's configuration.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| `prevent_destroy` CRD resources block the cutover apply | Explicit state-disowning step before editing `env.hcl` (U6) |
| **P0, found during deepening:** removing `github-arc-pat` from `helm_secrets` would let Terraform *destroy* (not just stop tracking) the live `arc-runners` namespace and Secret — neither carries `prevent_destroy` | Both explicitly disowned from Terraform state before the `env.hcl` edit, mirroring the CRD/`helm_release` disown pattern (U7, corrected) |
| Helm-release / ArgoCD-Application ownership collision during cutover | Eliminated via state-disown-and-adopt-in-place instead of destroy-then-recreate (U6, U7) — no downtime accepted or required |
| Kustomize `helmCharts:` inflation of OCI Helm charts (multiple still-open `argoproj/argo-cd` bugs around OCI auth propagation) | Avoided entirely: both migrated charts use ArgoCD's native multi-source Helm support instead of Kustomize wrapping |
| Adoption of already-live resources by a fresh ArgoCD sync could hit an unforeseen field-ownership conflict | Verify with a non-critical scratch resource first (see Open Questions); each cutover unit's Verification block confirms no unexpected recreation |
| KSOPS v4.5.1 / ArgoCD v3.3.2 compatibility not independently certified upstream | Scratch-app smoke test before any real secret depends on it (U4) |
| Shared `argocd-repo-server`: a bad KSOPS patch breaks manifest rendering cluster-wide | Smoke test in U4 before rollout; rollback = revert the additive `env.hcl` values |
| `--enable-exec` (required for KSOPS) is a repo-server-wide capability, not scoped to KSOPS's own invocation — broader than the decrypt-key-mixing risk alone | Accepted under the same solo-operator premise as the AGE-key risk below; needs a technical control (e.g. a pre-sync policy check) before any collaborator gets `apps/*`-only access |
| `apps`-tier manifests could technically decrypt with the `platform` AGE key (shared repo-server) | Accepted risk for solo-operator scope; documented follow-up if collaborators are added |
| Sealed Secrets controller key loss makes all `apps`-tier secrets unrecoverable | Back up sealing keypair immediately after first deploy (U5) |
| No rotation cadence defined for the platform AGE key pair or the GitOps repo deploy key | Accepted as an unscoped risk for now, same treatment as the admin-account row below; revisit if/when a rotation trigger (e.g. suspected compromise, collaborator offboarding) occurs |
| Terraform's ArgoCD auth depends indefinitely on the bootstrap admin account | Accepted for this plan; scoped `terraform` account + token deferred to follow-up |
| Corrected on deepening: Sealed Secrets' CRD is expected to install by default via ArgoCD's own Helm-source handling (not the `ServerSideApply` workaround an earlier pass assumed was required) | U5's smoke test confirms this against the pinned ArgoCD `v3.3.2`; `ServerSideApply=true` remains a documented fallback if the test reveals a real gap |
| `apps`-tier boundary only inspects resource *kind*, not Pod-spec fields (`privileged`, `hostPath`, `hostNetwork`) | `pod-security.kubernetes.io/enforce` labeling on `apps`-tier namespaces via `managed_namespace_metadata` (U2); validated against the real `gha-runner-scale-set` workload, not just a synthetic scratch app, in U7 |
| Third-party images (KSOPS init container, OCI runner charts) are pinned by mutable semver tag, not digest | Acceptable for now; consider digest pinning as a future hardening step for `platform`-tier components specifically (see Deferred to Follow-Up Work) |
| ApplicationSet git-generator default poll interval (~3 min) means "instant" app appearance isn't accurate | Documented expectation, not a defect; webhook alternative rejected to avoid reintroducing a `gateway-api`/DNS dependency |
| No rollback procedure defined for a cutover that fails after state has already been disowned | A drafted, dry-run rollback procedure is now an explicit prerequisite of U6 (added during deepening), not left purely as an open question |

---

## Documentation / Operational Notes

- Update `README.md`'s deployment-order list and repository-layout tree once `environments/staging/argocd-gitops` exists (U1).
- Add a corresponding "Environment-specific checks" line to `AGENTS.md` for the new stack (U1), per its existing per-stack `terragrunt validate` convention.
- Document the GitOps repo's required conventions (`apps/`/`platform/` layout, `.sops.yaml` two-tier rules, native-Helm-source `values.yaml` for chart-based apps, `kustomization.yaml` reserved for KSOPS-dependent apps) somewhere the user will see when they create that repo — this plan's Output Structure section is the canonical reference until then.
- Once this migration lands, capture it as an institutional learning (no `docs/solutions/` entries exist yet in this repo — this would be the first).

---

## Sources & References

- **Origin document:** [docs/brainstorms/argocd-gitops-migration-requirements.md](../brainstorms/argocd-gitops-migration-requirements.md)
- Related code: `modules/helm-charts/main.tf`, `modules/crds/main.tf`, `environments/staging/env.hcl`, `environments/staging/helm-charts/terragrunt.hcl`
- External docs: https://registry.terraform.io/providers/argoproj-labs/argocd/latest/docs, https://argo-cd.readthedocs.io/en/stable/user-guide/projects/, https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Security/, https://raw.githubusercontent.com/viaduct-ai/kustomize-sops/master/README.md, https://github.com/bitnami/sealed-secrets
