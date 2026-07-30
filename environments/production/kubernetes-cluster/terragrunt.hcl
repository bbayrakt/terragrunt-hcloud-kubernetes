# Include root configuration (remote state backend)
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
  repo_root = abspath(dirname(find_in_parent_folders("root.hcl")))
  env_dir   = dirname(find_in_parent_folders("env.hcl"))
}

# Use the remote terraform-hcloud-kubernetes module directly.
terraform {
  source = "git::https://github.com/hcloud-k8s/terraform-hcloud-kubernetes.git?ref=${include.env.locals.kubernetes_module_version}"

  before_hook "require_secrets" {
    commands = ["plan", "apply", "refresh", "import"]
    execute = [
      "bash",
      "-lc",
      "if [ ! -f '${local.repo_root}/secrets.yaml' ]; then echo 'secrets.yaml not found. Run: cp secrets.yaml.example secrets.yaml && sops -e -i secrets.yaml' >&2; exit 1; fi"
    ]
  }

  before_hook "save_kubeconfig_and_talosconfig" {
    commands = ["apply"]
    execute = [
      "bash",
      "-lc",
      "if [ -f '.terraform/modules/kubernetes/kubeconfig' ]; then cp .terraform/modules/kubernetes/kubeconfig '${local.env_dir}/kubeconfig'; fi && if [ -f '.terraform/modules/kubernetes/talosconfig' ]; then cp .terraform/modules/kubernetes/talosconfig '${local.env_dir}/talosconfig'; fi"
    ]
  }
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
