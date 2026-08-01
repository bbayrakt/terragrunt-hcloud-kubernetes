# Include root configuration
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Include environment-specific configuration from parent directory
include "env" {
  path   = find_in_parent_folders("env.hcl", find_in_parent_folders("environments"))
  expose = true
}

# Decrypt secrets directly using SOPS
locals {
  secrets                  = yamldecode(sops_decrypt_file(find_in_parent_folders("secrets.yaml")))
  fallback_kubeconfig_path = "${dirname(find_in_parent_folders("env.hcl"))}/kubeconfig${include.env.locals.environment_name == "production" ? "" : "-${include.env.locals.environment_name}"}"
}

# Use the gateway-api module
terraform {
  source = "../../../modules/gateway-api"
}

# Ensure kubernetes-cluster is deployed first
dependency "kubernetes_cluster" {
  config_path = "../kubernetes-cluster"

  # Lets `terragrunt run --all apply`/`destroy`/`plan` resolve this stack's config even when
  # kubernetes-cluster genuinely has no state yet (fresh environment) or none anymore (already
  # destroyed) -- Terragrunt always prefers the real output over this mock whenever the
  # dependency's state actually exists, so this has no effect on a live, applied cluster.
  mock_outputs = {
    kubeconfig_path = local.fallback_kubeconfig_path
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "apply", "destroy"]
}

# Pure ordering edges (no outputs consumed) for `terragrunt run --all apply`/`destroy` to
# sequence this stack correctly against its siblings -- matches README.md's documented
# deployment order (gateway-api applies last: cluster + CRDs + helm charts must exist first).
# Staging's equivalent block additionally lists karpenter, which production has no stack for.
dependencies {
  paths = ["../kubernetes-cluster", "../crds", "../helm-charts"]
}

# Generate providers.tf dynamically from Terragrunt
generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1"
    }
  }
}

provider "kubernetes" {
  config_path = "${try(dependency.kubernetes_cluster.outputs.kubeconfig_path, local.fallback_kubeconfig_path)}"
}

provider "helm" {
  kubernetes = {
    config_path = "${try(dependency.kubernetes_cluster.outputs.kubeconfig_path, local.fallback_kubeconfig_path)}"
  }
}
EOF
}

# Module inputs - loaded from env.hcl and dependencies
inputs = merge(
  include.env.inputs,
  {
    acme_email = local.secrets.acme_email
  }
)
