# Include root configuration
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Include environment-specific configuration from parent directory
include "env" {
  path = find_in_parent_folders("env.hcl", find_in_parent_folders("environments"))
  expose = true
}

# Decrypt secrets directly using SOPS
locals {
  secrets = yamldecode(sops_decrypt_file(find_in_parent_folders("secrets.yaml")))
}

# Use the gateway-api module
terraform {
  source = "../../../modules/gateway-api"
}

# Ensure kubernetes-cluster is deployed first
dependency "kubernetes_cluster" {
  config_path = "../kubernetes-cluster"
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
