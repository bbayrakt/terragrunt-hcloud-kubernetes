module "kubernetes" {
  source  = "hcloud-k8s/kubernetes/hcloud"
  version = "3.21.1"

  cluster_name = "k8s"
  hcloud_token = "your_hcloud_token"

  # Export configs for talosctl and kubectl (optional)
  cluster_kubeconfig_path  = "kubeconfig"
  cluster_talosconfig_path = "talosconfig"

  # Enable Cilium Gateway API and Cert Manager (optional)
  cert_manager_enabled       = true
  cilium_gateway_api_enabled = true

  cluster_delete_protection  = false

  control_plane_nodepools = [
    { name = "control", type = "cx33", location = "nbg1", count = 1 }
  ]
  worker_nodepools = [
    { name = "worker", type = "cx33", location = "nbg1", count = 3 }
  ]
}
