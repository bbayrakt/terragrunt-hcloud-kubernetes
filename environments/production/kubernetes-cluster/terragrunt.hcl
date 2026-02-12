# Include root configuration
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Include environment-specific configuration from parent directory
include "env" {
  path = find_in_parent_folders("env.hcl", find_in_parent_folders("environments"))
  expose = true
}

# Use the remote hcloud-k8s module
terraform {
  source = "../../../modules/kubernetes-cluster"
}

# Override kubeconfig paths to save in environment directory instead of cache
locals {
  env_dir = dirname(find_in_parent_folders("env.hcl"))
}

# Module inputs - loaded from env.hcl through include
inputs = merge(
  include.env.inputs,
  {
    # Override kubeconfig and talosconfig to save in environment directory
    cluster_kubeconfig_path  = "${local.env_dir}/kubeconfig"
    cluster_talosconfig_path = "${local.env_dir}/talosconfig"
  }
)
