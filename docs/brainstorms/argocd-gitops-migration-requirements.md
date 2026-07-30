---
date: 2026-07-30
topic: argocd-gitops-migration
---

# ArgoCD-Managed GitOps Migration for Non-Bootstrap Charts (Staging)

## Problem Frame

Today, staging installs four Helm charts the same way — as Terraform `helm_release` resources inside `modules/helm-charts`, driven by the `helm_charts` map in `environments/staging/env.hcl`: `external-dns`, `gha-runner-scale-set-controller`, `gha-runner-scale-set`, and `argocd` itself. Everything goes through Terragrunt regardless of whether it's genuinely a bootstrap dependency (ArgoCD must exist before it can deploy anything) or just an ordinary workload that happens to be packaged as a Helm chart.

This means every future chart addition requires a Terraform change, and there's no boundary preventing an ordinary app from installing cluster-scoped resources it shouldn't need. The goal is to shrink Terraform/Terragrunt's Helm footprint to only the charts that are truly bootstrap-critical, and let ArgoCD — configured from Terraform — take over deploying everything else, with a real enforced boundary between apps that need cluster-scoped install rights and apps that don't.

---

## Key Flows

- F1. Add a new `apps`-tier application
  - **Trigger:** Operator wants to deploy an ordinary app (Helm-chart-based or Kustomize-based) that needs no cluster-scoped permissions.
  - **Steps:** Create a new subdirectory under `apps/` in the GitOps repo with its manifests/values and any `SealedSecret` objects it needs → commit/push → the `apps` `ApplicationSet`'s git directory generator discovers the new directory automatically → ArgoCD creates and syncs the `Application` inside the `apps` `AppProject`.
  - **Outcome:** New app is running; it cannot create any cluster-scoped resource and cannot sync into a namespace outside the project's allow-list.
  - **Covered by:** R6, R8, R14

- F2. Add a new `platform`-tier application
  - **Trigger:** Operator wants to deploy something that genuinely needs cluster-scoped install rights (e.g. a controller that installs its own CRDs).
  - **Steps:** Create a new subdirectory under `platform/` with manifests/values, including any SOPS+KSOPS-encrypted secrets sealed with the platform-tier AGE key → commit/push → the `platform` `ApplicationSet`'s directory generator discovers it → ArgoCD syncs the `Application` inside the `platform` `AppProject`'s explicit cluster-resource whitelist.
  - **Outcome:** New privileged app is running; it still cannot create a cluster-scoped kind outside the whitelist.
  - **Covered by:** R5, R6, R7, R12, R13

- F3. Migrate the two existing runner charts off Terraform-managed Helm
  - **Trigger:** This effort's initial rollout.
  - **Steps:** Create the GitOps repo with `apps/`, `platform/`, and a two-tier `.sops.yaml` → apply the new Terraform stack (`argocd_project` x2, `argocd_application_set` x2, `argocd_repository`) → author `gha-runner-scale-set-controller` under `platform/` and `gha-runner-scale-set` under `apps/` in the GitOps repo → remove both from `helm_charts` in `env.hcl` so Terraform destroys the old `helm_release` resources.
  - **Outcome:** Both charts run as ArgoCD-managed apps; `helm_charts` in staging's `env.hcl` contains only `external-dns` and `argocd`.
  - **Covered by:** R7, R8, R9, R10, R11

---

## Requirements

**Terraform-managed ArgoCD bootstrap layer**
- R1. Terraform/Terragrunt continues to install `argocd`, `external-dns`, and `karpenter` as Helm releases for staging; no other chart is installed this way going forward.
- R2. A new Terragrunt-managed stack uses the official `argoproj-labs/argocd` Terraform provider, authenticated via port-forward against the existing cluster kubeconfig and ArgoCD's auto-generated initial-admin credential (not an exposed hostname/token, so this stack has no dependency on the `gateway-api` stack, DNS, or TLS).
- R3. This stack manages exactly two `argocd_project` resources (`apps`, `platform`), their paired `argocd_application_set` resources, and one `argocd_repository` resource registering the new GitOps repo. It does not author individual per-app `argocd_application` resources.

**Trust-tier boundary (AppProjects)**
- R4. The `apps` `AppProject` blocks creation of cluster-scoped resources (`cluster_resource_blacklist` covering all groups/kinds) and restricts sync destinations to an explicit namespace allow-list, not `*`.
- R5. The `platform` `AppProject` explicitly whitelists only the specific cluster-scoped kinds required by known platform-tier apps (e.g. `CustomResourceDefinition`, `ClusterRole`, `ClusterRoleBinding`) rather than allowing all cluster-scoped kinds.
- R6. Each `AppProject` is backed by its own `ApplicationSet` using a git directory generator watching a dedicated top-level path in the GitOps repo (`apps/*` for `apps`, `platform/*` for `platform`) — adding a new app requires only a new directory in the GitOps repo, not a Terraform change.

**Chart migration**
- R7. `gha-runner-scale-set-controller` moves from Terraform-managed Helm to an ArgoCD-managed app in the `platform` tier, because it installs its own CRDs (cluster-scoped).
- R8. `gha-runner-scale-set` moves from Terraform-managed Helm to an ArgoCD-managed app in the `apps` tier (it only creates namespaced custom-resource instances).
- R9. Both charts' Helm values move from `env.hcl`/Terragrunt into the GitOps repo's per-app configuration. ArgoCD/Helm installs and upgrades CRDs for these two charts directly; the existing Terraform `crds` stack is no longer involved for them.

**GitOps repository conventions**
- R10. A new, separate, dedicated git repository (not this Terraform repo) hosts app manifests — a mix of Helm-chart-based and Kustomize-based apps — organized under top-level `apps/` and `platform/` directories matching the two `ApplicationSet` generators.
- R11. The repository is registered with ArgoCD via Terraform's `argocd_repository` resource; its access credential is sourced from this repo's existing SOPS-encrypted `secrets.yaml`, the same way other secrets are handled today.

**Secrets management**
- R12. `platform`-tier app secrets are SOPS-encrypted using a dedicated AGE key pair, separate from this repo's existing Terragrunt AGE key, and decrypted in-cluster via the KSOPS Kustomize plugin patched into the *existing* Terraform-managed `argocd` Helm release's repo-server configuration (init container, volumes, build options) — no new Helm chart is introduced for this.
- R13. The `platform`-tier AGE private key is delivered to the cluster as a Terraform-created Kubernetes Secret mounted into `argocd-repo-server`, sourced from this repo's existing `secrets.yaml`. The corresponding public recipient key is checked into the GitOps repo's `.sops.yaml`.
- R14. `apps`-tier app secrets use Sealed Secrets instead of SOPS/AGE. The Sealed Secrets controller itself is deployed as a `platform`-tier ArgoCD app (not via Terragrunt), since it requires cluster-scoped resources (a CRD and a `ClusterRole`).

**Environment scope**
- R15. This work applies to staging only. Production's `helm_charts`/`helm_secrets` inputs remain undefined and are unaffected by this effort.

---

## Success Criteria

- Staging's `gha-runner-scale-set-controller` and `gha-runner-scale-set` run as ArgoCD-managed apps, not Terraform `helm_release` resources, with no manual `kubectl`/`argocd` CLI steps required to keep them in sync.
- `argocd`, `external-dns`, and `karpenter` remain the only Helm charts Terraform/Terragrunt installs directly for staging.
- An operator can add a new ordinary app under the GitOps repo's `apps/` directory and have it appear in the cluster automatically without touching Terraform, and that app cannot create any cluster-scoped resource.
- An operator can add a new privileged app under `platform/` when it genuinely needs cluster-scoped install rights, with that need reviewable via an explicit whitelist rather than an unrestricted grant.
- Secrets for both tiers can be committed to the GitOps repo safely (SOPS+AGE for `platform`, Sealed Secrets for `apps`), with no plaintext secret material ever stored in git.
- Planning has enough architectural clarity (provider, resource types, tier boundaries, secrets tooling, repo layout convention) to design the concrete Terraform module/stack and GitOps repo scaffold without inventing product decisions.

---

## Scope Boundaries

- Production is out of scope; its `helm_charts`/`helm_secrets` parity gap relative to staging is a separate, later effort.
- `argocd`, `external-dns`, and `karpenter` are not being moved to ArgoCD-managed delivery in this effort — they remain the accepted Terraform bootstrap exceptions.
- Creating the actual GitOps repository (and any CI around it) is not done as part of this brainstorm — the user will create it separately; this document defines the conventions it must follow.
- No changes to how the existing `crds` Terraform stack manages CRDs for charts that remain Terraform-managed.
- External Secrets Operator, OpenBao, and HashiCorp Vault were explicitly considered and declined in favor of Sealed Secrets for the `apps` tier (see Key Decisions) — not part of this effort.
- The exact `apps`-project namespace allow-list, the exact `platform`-project cluster-resource whitelist entries, and Sealed Secrets' scope mode are not decided here — left to planning.

---

## Key Decisions

| Tier | AppProject cluster-resource rule | Destination scope | Backing generator path | Secrets tool | Example chart |
|---|---|---|---|---|---|
| `apps` | Blacklist all cluster-scoped kinds | Explicit namespace allow-list | `apps/*` | Sealed Secrets | `gha-runner-scale-set` |
| `platform` | Explicit whitelist of needed kinds only | Broader, but still project-scoped | `platform/*` | SOPS + AGE (dedicated key) + KSOPS | `gha-runner-scale-set-controller`, Sealed Secrets controller itself |

- **Bootstrap exceptions stay Terraform-managed**: `argocd`, `external-dns`, and `karpenter` all have genuine chicken-and-egg dependencies — ArgoCD must exist before it can deploy anything, ExternalDNS underpins DNS resolution that ArgoCD's own route needs, and Karpenter must exist before most workloads can schedule (the `helm-charts` stack's before-hooks already gate on Karpenter readiness).
- **Terraform manages ArgoCD via `ApplicationSet`s + `AppProject`s, not per-app `argocd_application` resources**: keeps future app additions to a pure GitOps change (new directory in the repo) instead of a Terraform change per app.
- **`argoproj-labs/argocd` provider chosen over raw `kubernetes_manifest`**: gets ArgoCD-aware resources (`argocd_project`, `argocd_application_set`, `argocd_repository`) with schema validation, at the cost of needing the provider to authenticate to the live ArgoCD API.
- **Port-forward auth over exposed-hostname auth**: avoids making the new stack depend on `gateway-api`/DNS/TLS being live first, and reuses the auto-generated initial-admin secret instead of provisioning new credentials.
- **Cluster-scoped resource creation is the enforcement axis, not the templating engine**: both tiers can contain Helm-chart-based or Kustomize-based apps; what differs is the `AppProject`'s `cluster_resource_whitelist`/`blacklist`, which inspects the rendered manifest's kind regardless of how it was templated.
- **ArgoCD/Helm owns CRDs for ArgoCD-managed charts**: simpler than extending the existing Terraform `crds` stack to track a second, disjoint set of charts; accepted trade-off is losing that stack's `prevent_destroy` CRD safety net for these two charts specifically.
- **Two dedicated AGE keys (one per tier), separate from this repo's Terragrunt AGE key**: control who can *author/encrypt* secrets for which tier locally. Note: in-cluster, `argocd-repo-server` still needs both private keys available to decrypt either tier's manifests, since one repo-server renders both paths — the separation is an authoring-side boundary, not an in-cluster decrypt-time boundary.
- **Sealed Secrets over OpenBao for the `apps` tier**: OpenBao is fully self-hostable but requires a genuinely stateful service (storage backend, unsealing, HA, upgrades) plus External Secrets Operator to actually land values in Kubernetes — non-trivial operational cost for routine app secrets with no stated need for dynamic/leased credentials or an audit trail. Sealed Secrets is a single controller, needs no ArgoCD repo-server patch (a `SealedSecret` is just another manifest ArgoCD applies normally), and adds a bonus name+namespace scoping guardrail on top.
- **Sealed Secrets controller deployed via ArgoCD (`platform` tier), not Terragrunt**: it needs cluster-scoped resources (CRD, `ClusterRole`) to install, but isn't a bootstrap dependency — it can be one of the first `platform`-tier apps ArgoCD deploys once the stack is live, keeping it out of Terraform's Helm footprint.
- **Staging only**: production's `helm_charts`/`helm_secrets` maps don't exist yet; bringing production to parity is a distinct, deferred effort.

---

## Dependencies / Assumptions

- The GitOps repository must exist, with a working access credential, before the `argocd_repository`/`ApplicationSet` Terraform resources can be meaningfully applied — this is a real sequencing dependency for execution, not just documentation.
- Assumes patching the existing `argocd` Helm release's repo-server pod spec for KSOPS (init container, volumes, `configs.cm` build options) is compatible with the chart's current values (`global.domain`, `configs.params."server.insecure"`, `server.httproute.*`) without requiring a re-architecture of that release.
- Assumes the `argoproj-labs/argocd` Terraform provider version ultimately pinned supports `argocd_project`, `argocd_application_set`, and `argocd_repository` with the schema referenced during this brainstorm (verified against the provider's `master`-branch docs; pin and re-verify against an actual released version during planning).
- Assumes the Sealed Secrets controller, once deployed as a `platform`-tier app, becomes available before any `apps`-tier app that depends on a `SealedSecret` is expected to sync successfully (an ArgoCD sync-ordering concern, not a Terraform one).

---

## Outstanding Questions

### Resolve Before Planning

*(none — the architectural decisions in this document were resolved directly with the user)*

### Deferred to Planning

- [Affects R4][Needs research] What exact namespace allow-list should the `apps` `AppProject`'s `destination` restrict to initially?
- [Affects R5][Needs research] What exact `cluster_resource_whitelist` entries does `platform` need beyond `CustomResourceDefinition`/`ClusterRole`/`ClusterRoleBinding` (e.g. does the Sealed Secrets controller need anything else)?
- [Affects R2][Technical] What Terraform/Terragrunt module and stack name/location hosts the new `argocd_project`/`argocd_application_set`/`argocd_repository` resources, and where does it sit relative to `helm-charts` in the documented deploy order?
- [Affects R11][Technical] SSH deploy key vs. HTTPS token for the `argocd_repository` credential to the new GitOps repo?
- [Affects R12][Technical] Exact KSOPS version/image pin and the specific `argo-cd` chart values needed to patch `repo-server` for the currently pinned chart version (`9.4.5`).
- [Affects R14][Needs research] Sealed Secrets scope mode (default name+namespace vs. `namespace-wide`) and where its own Helm values/version are declared once it's a `platform`-tier app.
- [Affects R9][Technical] How does the existing `github-arc-pat` secret (currently pre-created by the Terraform `helm-charts` module) get re-homed once `gha-runner-scale-set` moves to the `apps` tier — as a `SealedSecret` authored in the GitOps repo, or still Terraform-created and referenced?

---

## Next Steps

-> `/ce-plan` for structured implementation planning
