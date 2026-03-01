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

  before_hook "require_cluster_kubeconfig" {
    commands = ["plan", "apply", "refresh", "import"]
    execute = [
      "bash",
      "-lc",
      "if [ ! -f '${local.fallback_kubeconfig_path}' ]; then echo 'Gateway API requires an existing Kubernetes cluster kubeconfig at ${local.fallback_kubeconfig_path}. Apply environments/staging/kubernetes-cluster first.' >&2; exit 1; fi"
    ]
  }
}

errors {
  retry "default_errors" {
    retryable_errors   = get_default_retryable_errors()
    max_attempts       = 3
    sleep_interval_sec = 15
  }

  retry "custom_errors" {
    retryable_errors = [
      "(?s).*API did not recognize GroupVersionKind from manifest \\(CRD may not be installed\\).*",
      "(?s).*no matches for kind \"Issuer\" in group \"cert-manager.io\".*",
      "(?s).*no matches for kind \"Gateway\" in group \"gateway.networking.k8s.io\".*",
      "(?s).*no matches for kind \"HTTPRoute\" in group \"gateway.networking.k8s.io\".*",
    ]
    max_attempts       = 6
    sleep_interval_sec = 15
  }
}

# Ensure kubernetes-cluster is deployed first
dependency "kubernetes_cluster" {
  config_path = "../kubernetes-cluster"

  mock_outputs = {
    kubeconfig_path = local.fallback_kubeconfig_path
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate"]
}

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
  }
}

provider "kubernetes" {
  config_path = "${try(dependency.kubernetes_cluster.outputs.kubeconfig_path, local.fallback_kubeconfig_path)}"
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
