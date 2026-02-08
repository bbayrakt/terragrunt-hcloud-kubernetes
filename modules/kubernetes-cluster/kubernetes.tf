module "kubernetes" {
  source  = "hcloud-k8s/kubernetes/hcloud"
  version = var.terraform_hcloud_kubernetes_module_version

  cluster_name = var.cluster_name
  hcloud_token = var.hcloud_token

  # Export configs for talosctl and kubectl (optional)
  cluster_kubeconfig_path  = var.cluster_kubeconfig_path
  cluster_talosconfig_path = var.cluster_talosconfig_path

  # Enable Cilium Gateway API and Cert Manager (optional)
  cert_manager_enabled       = var.cert_manager_enabled
  cilium_gateway_api_enabled = var.cilium_gateway_api_enabled

  cluster_delete_protection  = var.cluster_delete_protection

  control_plane_nodepools = var.control_plane_nodepools
  worker_nodepools = var.worker_nodepools
}
