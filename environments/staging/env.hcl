# Staging Environment Configuration
# This file contains all input variables for all modules in the staging environment

locals {
  environment_name = "staging"
  secrets          = yamldecode(sops_decrypt_file(find_in_parent_folders("secrets.yaml")))
}

inputs = {
  # Kubernetes Cluster Configuration
  
  # See https://github.com/hcloud-k8s/terraform-hcloud-kubernetes/releases
  terraform_hcloud_kubernetes_module_version = "3.21.3"

  cluster_name = "k8s-staging"
  hcloud_token = local.secrets.hcloud_token

  # Export configs for talosctl and kubectl
  cluster_kubeconfig_path  = "kubeconfig-staging"
  cluster_talosconfig_path = "talosconfig-staging"

  # Enable Cert Manager
  cert_manager_enabled = true

  # Cilium Transparent Encryption
  cilium_encryption_enabled = true
  cilium_encryption_type    = "ipsec"

  # Cilium Gateway API
  cilium_gateway_api_enabled = true

  # Talos Backup
  talos_backup_s3_region      = "us-east-1"
  talos_backup_s3_endpoint    = local.secrets.minio_endpoint
  talos_backup_s3_bucket      = "talos-backup"
  talos_backup_s3_access_key  = local.secrets.minio_access_key
  talos_backup_s3_secret_key  = local.secrets.minio_secret_key

  cluster_delete_protection = false

  # Smaller node pools for staging
  control_plane_nodepools = [
    {
      name     = "control"
      type     = "cx23"
      location = "nbg1"
      count    = 1
    }
  ]

  worker_nodepools = [
    {
      name     = "worker"
      type     = "cx33"
      location = "nbg1"
      count    = 2
    }
  ]

  cluster_autoscaler_nodepools = [
    {
      name     = "autoscaler"
      type     = "cx33"
      location = "nbg1"
      min      = 0
      max      = 4
      labels   = { "autoscaler-node" = "true" }
    }
  ]
}
