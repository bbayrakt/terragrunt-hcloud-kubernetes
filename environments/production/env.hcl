# Production Environment Configuration
# This file contains all input variables for all modules in the production environment

locals {
  environment_name = "production"
  secrets          = yamldecode(sops_decrypt_file(find_in_parent_folders("secrets.yaml")))
}

inputs = {
  # Kubernetes Cluster Configuration

  # See https://github.com/hcloud-k8s/terraform-hcloud-kubernetes/releases
  terraform_hcloud_kubernetes_module_version = "3.21.3"

  cluster_name = "k8s-production"
  hcloud_token = local.secrets.hcloud_token

  # Export configs for talosctl and kubectl
  cluster_kubeconfig_path  = "kubeconfig"
  cluster_talosconfig_path = "talosconfig"

  # Enable Cert Manager
  cert_manager_enabled = true

  # Cilium Gateway API
  cilium_gateway_api_enabled = true

  cluster_delete_protection = true

  # At least 3 control plane nodes are recommended for production clusters for high availability
  control_plane_nodepools = [
    {
      name     = "control"
      type     = "cx33"
      location = "nbg1"
      count    = 3
    }
  ]

  worker_nodepools = [
    {
      name     = "worker"
      type     = "cx33"
      location = "nbg1"
      count    = 3
    }
  ]
}
