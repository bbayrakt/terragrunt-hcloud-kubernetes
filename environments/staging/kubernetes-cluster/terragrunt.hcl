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

# Module inputs - loaded from env.hcl through include
inputs = merge(
  include.env.inputs,
  {
    # Override or add module-specific variables here if needed
  }
)
