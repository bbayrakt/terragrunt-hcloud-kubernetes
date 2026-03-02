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
  source = "../../../modules/helm-charts"

  before_hook "require_cluster_kubeconfig" {
    commands = ["plan", "apply", "refresh", "import"]
    execute = [
      "bash",
      "-lc",
      "if [ ! -f '${local.fallback_kubeconfig_path}' ]; then echo 'Helm charts module requires an existing Kubernetes cluster kubeconfig at ${local.fallback_kubeconfig_path}. Apply environments/staging/kubernetes-cluster first.' >&2; exit 1; fi"
    ]
  }

  before_hook "wait_for_gateway_api_crds" {
    commands = ["plan", "apply", "refresh", "import"]
    execute = [
      "bash",
      "-lc",
      <<-EOT
        if ! command -v kubectl >/dev/null 2>&1; then
          echo 'kubectl is required to verify Gateway API CRD readiness before helm chart operations.' >&2
          exit 1
        fi

        kubeconfig="${try(dependency.kubernetes_cluster.outputs.kubeconfig_path, local.fallback_kubeconfig_path)}"
        if [ ! -f "$kubeconfig" ]; then
          echo "Kubeconfig not found at $kubeconfig" >&2
          exit 1
        fi

        kubectl --kubeconfig "$kubeconfig" wait --for=condition=Established --timeout=5m crd/gateways.gateway.networking.k8s.io
        kubectl --kubeconfig "$kubeconfig" wait --for=condition=Established --timeout=5m crd/httproutes.gateway.networking.k8s.io
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

  retry "custom_errors" {
    retryable_errors = [
      "(?s).*API did not recognize GroupVersionKind from manifest \\(CRD may not be installed\\).*",
      "(?s).*no matches for kind \"Issuer\" in group \"cert-manager.io\".*",
      "(?s).*no matches for kind \"Gateway\" in (group|version) \"gateway\\.networking\\.k8s\\.io(/v[0-9a-z]+)?\".*",
      "(?s).*no matches for kind \"HTTPRoute\" in (group|version) \"gateway\\.networking\\.k8s\\.io(/v[0-9a-z]+)?\".*",
    ]
    max_attempts       = 6
    sleep_interval_sec = 15
  }
}

dependencies {
  paths = ["../kubernetes-cluster", "../crds"]
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
  charts  = include.env.inputs.helm_charts
  secrets = include.env.inputs.helm_secrets
}
