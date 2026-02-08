# Include root configuration
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Use the remote hcloud-k8s module
terraform {
  source = "../../../modules/kubernetes-cluster"
}

# Load secrets from root
locals {
  secrets = yamldecode(sops_decrypt_file(find_in_parent_folders("secrets.yaml")))
}

# Module inputs - Staging environment with smaller resources
inputs = {
  # See https://github.com/hcloud-k8s/terraform-hcloud-kubernetes/releases
  terraform_hcloud_kubernetes_module_version = "3.21.3"

  cluster_name = "k8s-staging"
  hcloud_token = local.secrets.hcloud_token

  # Export configs for talosctl and kubectl
  cluster_kubeconfig_path  = "kubeconfig-staging"
  cluster_talosconfig_path = "talosconfig-staging"

  # Enable Cilium Gateway API and Cert Manager
  cert_manager_enabled       = true
  cilium_gateway_api_enabled = true

  cluster_delete_protection = false

  # Smaller node pools for staging
  control_plane_nodepools = [
    { name = "control", type = "cx22", location = "nbg1", count = 1 }
  ]
  
  worker_nodepools = [
    { name = "worker", type = "cx22", location = "nbg1", count = 2 }
  ]
}
