---
date: 2026-07-31
topic: gitops-repo-scaffold
---

# GitOps Repository Scaffold (Reference)

Ready-to-copy content for the dedicated GitOps repository this migration depends on. That
repository doesn't exist yet — create it separately, then copy the files below into it before
applying `environments/staging/argocd-gitops`.

Origin: [docs/plans/2026-07-30-001-feat-argocd-gitops-migration-plan.md](plans/2026-07-30-001-feat-argocd-gitops-migration-plan.md)
(origin requirements: [docs/brainstorms/argocd-gitops-migration-requirements.md](brainstorms/argocd-gitops-migration-requirements.md)).

## Resolving the plan's deferred templating question

The plan's Open Questions left "the exact `ApplicationSet` templating mechanism for varying
`source.chart`/`source.repoURL` per app directory" to implementation. The `argocd_application_set`
Terraform resources actually implemented (`modules/argocd-gitops/main.tf`) use a single git-path
`source` per tier (`source.repo_url = <this GitOps repo>`, `source.path = "{{path}}"`) — ArgoCD
auto-detects the rendering tool from each directory's own content (`Chart.yaml` → Helm,
`kustomization.yaml` → Kustomize, otherwise plain manifests).

For the two Helm-chart-based apps below, each directory is a **thin wrapper chart**: a
`Chart.yaml` declaring one `dependencies` entry for the real upstream chart, plus `values.yaml`
nested under that dependency's alias. ArgoCD's repo-server resolves the dependency (`helm
dependency build`) and renders the fully-resolved chart via `helm template` — including its
`crds/` folder by default (see Key Technical Decisions #7) — with no vendored chart tarball
committed to git. This avoids the Kustomize `helmCharts:` + OCI risk surface the plan's Key
Technical Decisions #10 explicitly rejected, while staying compatible with the single-path-source
`ApplicationSet` template that's actually implemented.

Static extra manifests (like the `apps` tier's `SealedSecret`) go in the chart's own
`templates/` directory — Helm renders any plain YAML placed there unchanged alongside the
Go-templated files.

---

## `platform/gha-runner-scale-set-controller/`

`Chart.yaml`:

```yaml
apiVersion: v2
name: gha-runner-scale-set-controller-wrapper
version: 0.1.0
dependencies:
  - name: gha-runner-scale-set-controller
    version: "0.13.1"
    repository: "oci://ghcr.io/actions/actions-runner-controller-charts"
```

`values.yaml` (this chart currently takes no custom values — matches
`environments/staging/env.hcl`'s pre-migration block exactly):

```yaml
gha-runner-scale-set-controller: {}
```

## `platform/sealed-secrets/`

`Chart.yaml`:

```yaml
apiVersion: v2
name: sealed-secrets-wrapper
version: 0.1.0
dependencies:
  - name: sealed-secrets
    version: "2.19.1"
    repository: "https://bitnami.github.io/sealed-secrets"
```

`values.yaml`:

```yaml
sealed-secrets:
  fullnameOverride: sealed-secrets-controller
  image:
    registry: ghcr.io
    repository: bitnami/sealed-secrets-controller
```

> After first sync, back up the controller's auto-generated sealing keypair Secret
> immediately — losing it makes every previously-committed `SealedSecret` unrecoverable
> (see the plan's Risks & Dependencies).

## `apps/gha-runner-scale-set/`

`Chart.yaml`:

```yaml
apiVersion: v2
name: gha-runner-scale-set-wrapper
version: 0.1.0
dependencies:
  - name: gha-runner-scale-set
    version: "0.13.1"
    repository: "oci://ghcr.io/actions/actions-runner-controller-charts"
```

`values.yaml` (reproduces `environments/staging/env.hcl`'s pre-migration values 1:1 —
`githubConfigUrl` and `runnerGroup` need real values filled in; `githubConfigSecret` stays
`github-arc-pat`, produced by the `SealedSecret` below, not by Terraform):

```yaml
gha-runner-scale-set:
  githubConfigUrl: "<your github org/repo URL>"
  githubConfigSecret: github-arc-pat
  runnerGroup: "Default"
  minRunners: 1
```

`templates/sealed-secret.yaml` (produces the `github-arc-pat` Secret ArgoCD adopts in place of
the Terraform-created one of the same name — see Key Technical Decisions #11; generate this
file's `encryptedData` with `kubeseal` once the Sealed Secrets controller from
`platform/sealed-secrets/` is running):

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: github-arc-pat
  namespace: arc-runners
spec:
  encryptedData:
    github_token: <kubeseal output — do not hand-write this>
  template:
    metadata:
      name: github-arc-pat
      namespace: arc-runners
    type: Opaque
```

---

## `.sops.yaml` (repo root)

Two-tier AGE recipients — `platform/` encrypted with the platform-tier key, `apps/` needs no
SOPS rule at all since `apps`-tier secrets are Sealed Secrets, not SOPS-encrypted:

```yaml
creation_rules:
  - path_regex: platform/.*\.sops\.yaml$
    age: "<platform-tier AGE public recipient — from age-keygen, matches the private key in
      secrets.yaml's platform_sops_age_private_key>"
```

(No `apps/` rule — Sealed Secrets are the `apps`-tier mechanism, not SOPS/KSOPS. If a future
`platform`-tier app needs a SOPS-encrypted value, name the file `*.sops.yaml` under `platform/`
so this rule picks it up, and reference it via a KSOPS generator per the upstream
`viaduct-ai/kustomize-sops` README.)

---

## Full expected layout

    apps/
        gha-runner-scale-set/
            Chart.yaml
            values.yaml
            templates/
                sealed-secret.yaml
    platform/
        gha-runner-scale-set-controller/
            Chart.yaml
            values.yaml
        sealed-secrets/
            Chart.yaml
            values.yaml
    .sops.yaml
