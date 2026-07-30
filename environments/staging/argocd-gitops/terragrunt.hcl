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

        if ! kubectl --kubeconfig "$kubeconfig" -n argocd get secret argocd-initial-admin-secret >/dev/null 2>&1; then
          echo "argocd-initial-admin-secret not found in namespace argocd -- has environments/staging/helm-charts been applied?" >&2
          exit 1
        fi

        password_file="${local.argocd_admin_password_file}"
        umask 077
        kubectl --kubeconfig "$kubeconfig" -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d > "$password_file"
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
  config_path                 = "${try(dependency.kubernetes_cluster.outputs.kubeconfig_path, local.fallback_kubeconfig_path)}"

  username = "admin"
  password = trimspace(try(file("${local.argocd_admin_password_file}"), "placeholder-for-validate"))
}
EOF
}

inputs = {
  gitops_repo_url             = include.env.inputs.gitops_repo_url
  gitops_repo_ssh_private_key = include.env.inputs.gitops_repo_ssh_private_key
}
