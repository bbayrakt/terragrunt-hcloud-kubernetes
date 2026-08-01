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
}

terraform {
  source = "../../../modules/crds"

  before_hook "require_cluster_kubeconfig" {
    commands = ["plan", "apply", "refresh", "import"]
    execute = [
      "bash",
      "-lc",
      "if [ ! -f '${local.fallback_kubeconfig_path}' ]; then echo 'CRDs module requires an existing Kubernetes cluster kubeconfig at ${local.fallback_kubeconfig_path}. Apply environments/production/kubernetes-cluster first.' >&2; exit 1; fi"
    ]
  }

  before_hook "require_cluster_ready_for_crds" {
    commands = ["plan", "apply", "refresh", "import"]
    execute = [
      "bash",
      "-lc",
      <<-EOT
        if ! command -v kubectl >/dev/null 2>&1; then
          echo 'kubectl is required to verify Kubernetes API readiness before applying CRDs.' >&2
          exit 1
        fi

        kubeconfig="${try(dependency.kubernetes_cluster.outputs.kubeconfig_path, local.fallback_kubeconfig_path)}"
        if [ ! -f "$kubeconfig" ]; then
          echo "Kubeconfig not found at $kubeconfig" >&2
          exit 1
        fi

        kubectl --kubeconfig "$kubeconfig" version --request-timeout=15s >/dev/null
      EOT
    ]
  }
}

dependencies {
  paths = ["../kubernetes-cluster"]
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

inputs = {
  charts = include.env.inputs.helm_charts
}