# Include root configuration
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Include environment-specific configuration from parent directory
include "env" {
  path   = find_in_parent_folders("env.hcl", find_in_parent_folders("environments"))
  expose = true
}

locals {
  fallback_kubeconfig_path = "${dirname(find_in_parent_folders("env.hcl"))}/kubeconfig${include.env.locals.environment_name == "production" ? "" : "-${include.env.locals.environment_name}"}"

  # Git-ignored, stack-local file the before_hook below writes the ArgoCD admin password into.
  # Never committed (see repo .gitignore). Read by the generated provider block via file()/try().
  argocd_admin_password_file = "${get_terragrunt_dir()}/.argocd-admin-password"

  # Explicit kubernetes{} connection details (host/CA/client cert), extracted directly from the
  # kubeconfig file, rather than relying on the argocd provider's own config_path kubeconfig
  # parsing. Found via live validation: this provider version fails port-forward setup against
  # this cluster's (Talos-generated, ECDSA) CA when using config_path alone ("x509: certificate
  # signed by unknown authority... ECDSA verification failure"), but works when the host/CA/
  # client cert are passed explicitly -- matches the pattern the provider's own community issues
  # use for non-config_path clusters (e.g. EKS). Wrapped in try() with empty-string fallbacks so
  # offline `terragrunt hcl validate`/`format` stay static-safe when no kubeconfig exists yet.
  # Note: Terragrunt locals cannot reference `dependency.*` outputs, so this always reads from
  # the fallback path (which is what `dependency.kubernetes_cluster.outputs.kubeconfig_path`
  # resolves to in practice once that stack has been applied).
  kubeconfig_data     = try(yamldecode(file(local.fallback_kubeconfig_path)), null)
  k8s_api_host        = try(local.kubeconfig_data.clusters[0].cluster.server, "")
  k8s_cluster_ca_cert = try(base64decode(local.kubeconfig_data.clusters[0].cluster["certificate-authority-data"]), "")
  k8s_client_cert     = try(base64decode(local.kubeconfig_data.users[0].user["client-certificate-data"]), "")
  k8s_client_key      = try(base64decode(local.kubeconfig_data.users[0].user["client-key-data"]), "")
}

terraform {
  source = "../../../modules/argocd-gitops"

  before_hook "require_cluster_kubeconfig" {
    commands = ["plan", "apply", "refresh", "import"]
    execute = [
      "bash",
      "-lc",
      "if [ ! -f '${local.fallback_kubeconfig_path}' ]; then echo 'ArgoCD GitOps module requires an existing Kubernetes cluster kubeconfig at ${local.fallback_kubeconfig_path}. Apply environments/staging/kubernetes-cluster and environments/staging/helm-charts first.' >&2; exit 1; fi"
    ]
  }

  # Fetches ArgoCD's auto-generated initial-admin password and writes it to a git-ignored local
  # file (never Terragrunt/Terraform stdout) for the provider block to read via file()/try().
  # Deliberately NOT threaded through a `locals` block with run_cmd(), which would re-evaluate on
  # every HCL parse -- including `terragrunt hcl validate` -- breaking this repo's static-safe
  # validation convention (AGENTS.md). Scoped to the same commands as every other before_hook in
  # this repo, excluding `validate`.
  before_hook "fetch_argocd_admin_password" {
    commands = ["plan", "apply", "refresh", "import"]
    execute = [
      "bash",
      "-lc",
      <<-EOT
        set -euo pipefail

        if ! command -v kubectl >/dev/null 2>&1; then
          echo 'kubectl is required to fetch the ArgoCD initial-admin password.' >&2
          exit 1
        fi

        kubeconfig="${try(dependency.kubernetes_cluster.outputs.kubeconfig_path, local.fallback_kubeconfig_path)}"
        if [ ! -f "$kubeconfig" ]; then
          echo "Kubeconfig not found at $kubeconfig" >&2
          exit 1
        fi

        if ! kubectl --kubeconfig "$kubeconfig" --request-timeout=30s -n argocd get secret argocd-initial-admin-secret >/dev/null 2>&1; then
          echo "argocd-initial-admin-secret not found in namespace argocd -- has environments/staging/helm-charts been applied?" >&2
          exit 1
        fi

        password_file="${local.argocd_admin_password_file}"
        umask 077
        password="$(kubectl --kubeconfig "$kubeconfig" --request-timeout=30s -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
        if [ -z "$password" ]; then
          echo "argocd-initial-admin-secret exists but its 'password' key is empty -- refusing to write an empty credential file." >&2
          exit 1
        fi
        printf '%s' "$password" > "$password_file"
      EOT
    ]
  }
}

errors {
  retry "default_errors" {
    retryable_errors   = get_default_retryable_errors()
    max_attempts       = 3
    sleep_interval_sec = 15
  }
}

dependencies {
  paths = ["../kubernetes-cluster", "../helm-charts"]
}

dependency "kubernetes_cluster" {
  config_path = "../kubernetes-cluster"

  mock_outputs = {
    kubeconfig_path = local.fallback_kubeconfig_path
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate"]
}

generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
terraform {
  required_providers {
    argocd = {
      source  = "argoproj-labs/argocd"
      version = "7.15.3"
    }
  }
}

provider "argocd" {
  port_forward_with_namespace = "argocd"
  plain_text                  = true

  username = "admin"
  password = trimspace(try(file("${local.argocd_admin_password_file}"), "placeholder-for-validate"))

  kubernetes {
    host                   = ${jsonencode(local.k8s_api_host)}
    cluster_ca_certificate = ${jsonencode(local.k8s_cluster_ca_cert)}
    client_certificate     = ${jsonencode(local.k8s_client_cert)}
    client_key             = ${jsonencode(local.k8s_client_key)}
  }
}
EOF
}

inputs = {
  gitops_repo_url             = include.env.inputs.gitops_repo_url
  gitops_repo_ssh_private_key = include.env.inputs.gitops_repo_ssh_private_key
}
