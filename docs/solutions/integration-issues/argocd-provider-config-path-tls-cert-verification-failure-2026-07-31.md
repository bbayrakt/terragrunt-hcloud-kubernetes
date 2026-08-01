---
title: ArgoCD Terraform Provider Fails TLS Verification Against a Talos ECDSA Cluster CA via config_path
date: 2026-07-31
category: docs/solutions/integration-issues
module: argocd-gitops-stack
problem_type: integration_issue
component: tooling
symptoms:
  - "terraform apply fails identically on every argocd-provider resource (argocd_project, argocd_application_set, argocd_repository)"
  - "Error: failed to create new API client -- tls: failed to verify certificate: x509: certificate signed by unknown authority (possibly because of \"x509: ECDSA verification failure\")"
  - "Failure only surfaces at terraform apply (live connectivity) -- terragrunt hcl validate / terraform validate give no warning"
  - "The identical kubeconfig works fine via kubectl and via the hashicorp/kubernetes and hashicorp/helm providers against the same cluster"
root_cause: config_error
resolution_type: config_change
severity: high
related_components: [terragrunt, kubernetes-provider, talos]
tags: [argocd, terraform-provider, tls, x509, ecdsa, talos, kubeconfig, port-forward]
---

# ArgoCD Terraform Provider Fails TLS Verification Against a Talos ECDSA Cluster CA via config_path

## Problem

The `argoproj-labs/argocd` Terraform provider (v7.15.3, `port_forward_with_namespace` auth mode) fails to authenticate against a real Talos-based Kubernetes cluster when configured via its top-level `config_path` attribute — the same pattern already working for the `hashicorp/kubernetes` and `hashicorp/helm` providers against the identical kubeconfig in the same Terragrunt stack.

## Symptoms

- `terraform apply` fails identically on **every** `argocd`-provider resource (`argocd_project`, `argocd_application_set`, `argocd_repository`) in the stack — not one specific resource.
- Exact error:
  ```
  Error: failed to create new API client
  Get "https://<ip>:6443/api/v1/namespaces/argocd/pods?labelSelector=app.kubernetes.io%2Fname%3Dargocd-server":
  tls: failed to verify certificate: x509: certificate signed by unknown authority
  (possibly because of "x509: ECDSA verification failure" while trying to verify
  candidate authority certificate "kubernetes")
  ```
- The failure only surfaces at `terraform apply` (live connectivity) — `terragrunt hcl validate` / `terraform validate` give no warning at all, since neither requires a live cluster connection.
- The exact same kubeconfig works fine for every other tool/provider used against the same cluster at the same time, isolating the failure specifically to this provider's `config_path` handling.

## What Didn't Work

- **Re-checking/regenerating the kubeconfig** — ruled out immediately: `kubectl --kubeconfig <same-path> get pods` succeeded at the exact same moment the `argocd` provider failed, proving the kubeconfig and cluster CA were valid and not corrupted.
- **Searching upstream GitHub issues** (`argoproj-labs/terraform-provider-argocd` issues #415, #631 — general "port_forward doesn't work" reports) — described related but not identical symptoms ("failed to create new session client", generic connection failures), with no fix pinpointing this exact ECDSA/`config_path` failure mode.
- **Assuming a cluster-side certificate defect** — ruled out: the `hashicorp/kubernetes` and `hashicorp/helm` providers, configured with the identical `config_path`, connected to the same cluster without error at the same time.

## Solution

Stop relying on the `argocd` provider's top-level `config_path` attribute. Instead, explicitly parse the kubeconfig file in Terragrunt `locals` and feed the connection details into the provider's `kubernetes { }` sub-block — a structurally distinct construct from `config_path` (the sub-block has its own explicit connection attributes and no `config_path` field of its own).

`environments/staging/argocd-gitops/terragrunt.hcl`:

```hcl
locals {
  kubeconfig_data     = try(yamldecode(file(local.fallback_kubeconfig_path)), null)
  k8s_api_host        = try(local.kubeconfig_data.clusters[0].cluster.server, "")
  k8s_cluster_ca_cert = try(base64decode(local.kubeconfig_data.clusters[0].cluster["certificate-authority-data"]), "")
  k8s_client_cert     = try(base64decode(local.kubeconfig_data.users[0].user["client-certificate-data"]), "")
  k8s_client_key      = try(base64decode(local.kubeconfig_data.users[0].user["client-key-data"]), "")
}
```

Generated provider block:

```hcl
provider "argocd" {
  port_forward_with_namespace = "argocd"
  plain_text                  = true
  username                    = "admin"
  password                    = trimspace(try(file(local.argocd_admin_password_file), "placeholder-for-validate"))

  kubernetes {
    host                   = local.k8s_api_host
    cluster_ca_certificate = local.k8s_cluster_ca_cert
    client_certificate     = local.k8s_client_cert
    client_key             = local.k8s_client_key
  }
}
```

Every `local` is wrapped in `try(...)` so `terragrunt hcl validate`/`format` remain static-safe when no live kubeconfig exists yet — matching this repo's existing offline-validation convention (see `AGENTS.md`: "use deterministic local fallbacks... so validation remains static-safe").

(Note: the real generated provider block wraps each `local.*` value in `jsonencode(...)` before interpolating it into the Terragrunt `generate "providers"` heredoc, since heredoc interpolation needs a properly-escaped literal. The snippet above shows the simpler, direct form for a normal (non-heredoc-generated) provider block — copy the `jsonencode(...)` wrapping if reusing this inside a `generate` block instead.)

Result: `terraform apply` succeeded cleanly against the real cluster on the first attempt after this change, confirmed live via `kubectl get appproject,applicationset -n argocd -o yaml` showing every resource created with the correct spec.

## Why This Works

Talos generates an ECDSA-signed cluster CA. The `argoproj-labs/argocd` provider's internal Kubernetes client construction, when driven purely by `config_path`, mishandles verifying an ECDSA-signed CA certificate — even though `kubectl` and the standard `hashicorp/kubernetes`/`hashicorp/helm` providers parse and trust the identical CA without issue. This suggests the provider's `config_path` code path is less exercised / more fragile than its explicit-connection-details code path, at least for non-mainstream (e.g. ECDSA/Talos) CAs. This inference was corroborated by community examples of the same provider connecting to AWS EKS clusters, which likewise always pass `host`/`cluster_ca_certificate`/token explicitly rather than relying on ambient kubeconfig-file resolution — the explicit-attributes path is the better-supported, more battle-tested route for this provider. Supplying `host`, `cluster_ca_certificate`, `client_certificate`, and `client_key` explicitly bypasses whatever CA-verification logic is defective in the `config_path` path.

## Prevention

- When integrating the `argoproj-labs/argocd` Terraform provider (or any provider offering both a `config_path`-style attribute and an explicit-connection-details block, e.g. `kubernetes { }`) against a Talos-generated or otherwise non-mainstream-CA cluster, **prefer explicit `host`/`cluster_ca_certificate`/`client_certificate`/`client_key` extraction from the kubeconfig over `config_path`** — especially when a non-standard auth/connection mode (like `port_forward_with_namespace`) is in play.
- Standardize this pattern (parse kubeconfig via `yamldecode(file(...))` in `locals`, `try()`-wrap each derived value for offline-validate safety, feed explicit values into the provider block) as the default for any *new* provider integration in this repo that talks to the cluster API, rather than assuming parity with `hashicorp/kubernetes`/`hashicorp/helm`'s `config_path` behavior.
- Always test a new provider's connectivity against a **real, live cluster** early — not just `terraform validate`/`terragrunt hcl validate` — since this class of bug (CA/TLS verification mismatch) only surfaces at actual `apply` time and is invisible to static validation. (This exact bug, plus two others, was found only by actually deploying a real cluster and applying against it — see the plan doc's Key Technical Decisions for the fuller story.)

## Related Issues

- No related GitHub issues found in this repo (`bbayrakt/terragrunt-hcloud-kubernetes`) — searched for `argocd provider certificate`, `x509 certificate`, `talos kubeconfig`, `kubernetes provider`, no results.
- Upstream `argoproj-labs/terraform-provider-argocd` issues #415 and #631 describe adjacent-but-not-identical port-forward connectivity difficulties with this provider; neither pinpoints this exact ECDSA/`config_path` failure mode.
- `docs/plans/2026-07-30-001-feat-argocd-gitops-migration-plan.md` (Unit U1) covers ArgoCD provider *authentication* (fetching the admin password), a related but distinct concern from the TLS/certificate issue documented here.
