variable "terraform_hcloud_kubernetes_module_version" {
  description = "Version of the hcloud-k8s Kubernetes module to use. Set to 'latest' for the latest version."
  type        = string
}

variable "cluster_name" {
  description = "Name of the Kubernetes cluster to create in Hetzner Cloud."
  type        = string
}

variable "hcloud_token" {
  description = "Hetzner Cloud API token with permissions to manage resources for the Kubernetes cluster."
  type        = string
  sensitive   = true
}

variable "cluster_kubeconfig_path" {
  description = "File path to export the Kubernetes kubeconfig for cluster access."
  type        = string
}

variable "cluster_talosconfig_path" {
  description = "File path to export the Talos OS configuration for cluster management."
  type        = string
}

variable "cert_manager_enabled" {
  description = "Whether to enable Cert Manager for automatic TLS certificate management in the cluster."
  type        = bool
  default     = true
}

variable "cilium_gateway_api_enabled" {
  description = "Whether to enable Cilium's Gateway API support for advanced traffic routing and load balancing."
  type        = bool
  default     = true
}

variable "cluster_delete_protection" {
  description = "Whether to enable delete protection for the Kubernetes cluster to prevent accidental deletion."
  type        = bool
  default     = false
}

variable "control_plane_nodepools" {
  description = "List of node pools for control plane nodes, each with name, type, location, and count."
  type = list(object({
    name     = string
    type     = string
    location = string
    count    = number
  }))
}

variable "worker_nodepools" {
  description = "List of node pools for worker nodes, each with name, type, location, and count."
  type = list(object({
    name     = string
    type     = string
    location = string
    count    = number
  }))
}