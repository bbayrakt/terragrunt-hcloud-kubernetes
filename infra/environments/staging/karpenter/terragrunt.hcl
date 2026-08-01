include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path   = find_in_parent_folders("env.hcl", find_in_parent_folders("environments"))
  expose = true
}

locals {
  env_dir                   = dirname(find_in_parent_folders("env.hcl"))
  fallback_kubeconfig_path  = "${local.env_dir}/kubeconfig-staging"
  fallback_cluster_endpoint = "https://127.0.0.1:6443"
}

terraform {
  source = "../../../modules/karpenter"

  before_hook "require_cluster_kubeconfig" {
    commands = ["plan", "apply", "refresh", "import"]
    execute = [
      "bash",
      "-lc",
      "if [ ! -f '${local.fallback_kubeconfig_path}' ]; then echo 'Karpenter requires an existing staging kubeconfig. Apply ../kubernetes-cluster first.' >&2; exit 1; fi"
    ]
  }

  before_hook "require_cluster_api" {
    commands = ["plan", "apply", "refresh", "import"]
    execute = [
      "bash",
      "-lc",
      <<-EOT
        if ! command -v kubectl >/dev/null 2>&1; then
          echo 'kubectl is required to verify staging API readiness.' >&2
          exit 1
        fi
        kubectl --kubeconfig '${local.fallback_kubeconfig_path}' version --request-timeout=15s >/dev/null
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
    kubeconfig_path                 = local.fallback_kubeconfig_path
    talos_machine_secrets           = {}
    control_plane_private_ipv4_list = ["127.0.0.1"]
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "apply", "destroy"]
}

generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    terraform {
      required_providers {
        hcloud = {
          source  = "hetznercloud/hcloud"
          version = "~> 1.67.0"
        }
        helm = {
          source  = "hashicorp/helm"
          version = "~> 3.2.0"
        }
        kubernetes = {
          source  = "hashicorp/kubernetes"
          version = "~> 3.0"
        }
        talos = {
          source  = "siderolabs/talos"
          version = "0.11.0"
        }
      }
    }

    provider "hcloud" {
      token = "${include.env.inputs.hcloud_token}"
    }

    provider "helm" {
      kubernetes = {
        config_path = "${local.fallback_kubeconfig_path}"
      }
    }

    provider "kubernetes" {
      config_path = "${try(dependency.kubernetes_cluster.outputs.kubeconfig_path, local.fallback_kubeconfig_path)}"
    }
  EOF
}

inputs = {
  cluster_name          = include.env.locals.cluster_name
  hcloud_token          = include.env.inputs.hcloud_token
  kubeconfig_path       = local.fallback_kubeconfig_path
  talos_version         = try(include.env.inputs.talos_version, "v1.13.5")
  kubernetes_version    = try(include.env.inputs.kubernetes_version, "v1.34.9")
  talos_machine_secrets = dependency.kubernetes_cluster.outputs.talos_machine_secrets
  cluster_endpoint      = "https://${try(dependency.kubernetes_cluster.outputs.control_plane_private_ipv4_list[0], "127.0.0.1")}:6443"
  network_name          = include.env.locals.cluster_name

  # The following affect the managed HCloudNodeClass and/or NodePool and
  # have sane module defaults (locations: ["fsn1"], architectures: ["amd64"],
  # server_types: ["cpx32"], worker_cpu_limit: "16",
  # public_ipv4_enabled/public_ipv6_enabled: true). Passing an explicit null
  # when unset in env.hcl causes the module default to be used instead. The
  # HCloudNodeClass image selector is intentionally not configurable here: it
  # always resolves to the exact Talos image the kubernetes-cluster module
  # built for this cluster_name/talos_version (see modules/karpenter
  # data.hcloud_image.cluster_talos).
  locations           = try(include.env.inputs.karpenter_locations, null)
  architectures       = try(include.env.inputs.karpenter_architectures, null)
  server_types        = try(include.env.inputs.karpenter_server_types, null)
  worker_cpu_limit    = try(include.env.inputs.karpenter_worker_cpu_limit, null)
  public_ipv4_enabled = try(include.env.inputs.karpenter_public_ipv4_enabled, include.env.inputs.talos_public_ipv4_enabled, null)
  public_ipv6_enabled = try(include.env.inputs.karpenter_public_ipv6_enabled, include.env.inputs.talos_public_ipv6_enabled, null)

  # Chart version is mandatory: no fallback is provided here or in the
  # module, so it must be set explicitly in env.hcl.
  chart_version = include.env.inputs.karpenter_chart_version

  # The following have sane module defaults (release_name/helm_chart:
  # "karpenter-provider-hetzner", namespace: "karpenter", create_namespace:
  # true, helm_repository: "oci://ghcr.io/paperclipinc/charts",
  # hcloud_token_secret_name: "karpenter-hcloud-token"). Passing an explicit
  # null when unset in env.hcl causes the module default to be used instead.
  release_name             = try(include.env.inputs.karpenter_release_name, null)
  namespace                = try(include.env.inputs.karpenter_namespace, null)
  create_namespace         = try(include.env.inputs.karpenter_create_namespace, null)
  helm_repository          = try(include.env.inputs.karpenter_helm_repository, null)
  helm_chart               = try(include.env.inputs.karpenter_helm_chart, null)
  hcloud_token_secret_name = try(include.env.inputs.karpenter_hcloud_token_secret_name, null)

  # Environment label applied to the HCloudNodeClass; always available from
  # env.hcl's own locals, so it is passed through directly (mandatory, no
  # module default).
  environment = include.env.locals.environment_name

  # HCloudNodeClass / NodePool customization. Sane module defaults apply
  # (nodeclass_name: "talos-default", nodepool_name: "default", labels: {},
  # spec overrides: {}). Passing an explicit null when unset in env.hcl
  # causes the module default to be used instead.
  nodeclass_name           = try(include.env.inputs.karpenter_nodeclass_name, null)
  nodeclass_labels         = try(include.env.inputs.karpenter_nodeclass_labels, null)
  nodeclass_spec_overrides = try(include.env.inputs.karpenter_nodeclass_spec_overrides, null)
  nodepool_name            = try(include.env.inputs.karpenter_nodepool_name, null)
  nodepool_template_labels = try(include.env.inputs.karpenter_nodepool_template_labels, null)
  nodepool_spec_overrides  = try(include.env.inputs.karpenter_nodepool_spec_overrides, null)
}
