# Pass through outputs from hcloud-k8s module

output "kubeconfig" {
  description = "Kubeconfig content for the Kubernetes cluster"
  value       = module.kubernetes.kubeconfig
  sensitive   = true
}

output "talosconfig" {
  description = "Talosconfig content for talosctl management"
  value       = module.kubernetes.talosconfig
  sensitive   = true
}

output "kubeconfig_data" {
  description = "Structured kubeconfig data for programmatic access"
  value       = module.kubernetes.kubeconfig_data
  sensitive   = true
}

output "control_plane_private_ipv4_list" {
  description = "List of private IPv4 addresses for control plane nodes"
  value       = module.kubernetes.control_plane_private_ipv4_list
}

output "control_plane_public_ipv4_list" {
  description = "List of public IPv4 addresses for control plane nodes"
  value       = module.kubernetes.control_plane_public_ipv4_list
}

output "worker_private_ipv4_list" {
  description = "List of private IPv4 addresses for worker nodes"
  value       = module.kubernetes.worker_private_ipv4_list
}

output "worker_public_ipv4_list" {
  description = "List of public IPv4 addresses for worker nodes"
  value       = module.kubernetes.worker_public_ipv4_list
}

output "kube_api_load_balancer" {
  description = "Kubernetes API load balancer details"
  value       = module.kubernetes.kube_api_load_balancer
}

output "cilium_encryption_info" {
  description = "Cilium encryption configuration information"
  value       = module.kubernetes.cilium_encryption_info
}

output "load_balancer_ip" {
  description = "Public IP address of the Kubernetes API load balancer"
  value       = try(module.kubernetes.kube_api_load_balancer.public_net[0].ipv4.ip, null)
}

output "kubeconfig_path" {
  description = "Path to the kubeconfig file on the local filesystem"
  value       = var.cluster_kubeconfig_path
}
