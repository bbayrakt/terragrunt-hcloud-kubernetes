variable "cluster_name" {
  description = "Cluster name used to scope Karpenter-managed Hetzner servers."
  type        = string
}

variable "hcloud_token" {
  description = "Hetzner Cloud API token."
  type        = string
  sensitive   = true
}

variable "kubeconfig_path" {
  description = "Path to the cluster kubeconfig."
  type        = string
}

variable "talos_version" {
  description = "Talos version used for the worker machine configuration and image selector."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version used for the worker machine configuration."
  type        = string
}

variable "talos_machine_secrets" {
  description = "Sensitive Talos machine secrets from the cluster module."
  type        = any
  sensitive   = true
}

variable "cluster_endpoint" {
  description = "Private Kubernetes API endpoint used by worker Talos configuration."
  type        = string
}

variable "network_name" {
  description = "Existing Hetzner private network name."
  type        = string
}

variable "location" {
  description = "Hetzner location for Karpenter workers."
  type        = string
  default     = "fsn1"
}

variable "server_family" {
  description = "Hetzner server family allowed by the NodePool."
  type        = string
  default     = "cpx"
}

variable "server_type" {
  description = "Specific server type used to cap the initial staging pool."
  type        = string
  default     = "cpx32"
}

variable "worker_cpu_limit" {
  description = "Maximum total CPU Karpenter may provision for the staging pool."
  type        = string
  default     = "16"
}

variable "image_selector" {
  description = "Optional additional image label selector. The module adds the cluster Talos labels."
  type        = map(string)
  default     = {}
}

variable "public_ipv4_enabled" {
  description = "Whether Karpenter workers receive public IPv4 addresses."
  type        = bool
  default     = true
}

variable "public_ipv6_enabled" {
  description = "Whether Karpenter workers receive public IPv6 addresses."
  type        = bool
  default     = true
}

variable "controller_values" {
  description = "Additional Helm values for the Karpenter provider controller."
  type        = any
  default     = {}
}

variable "release_name" {
  description = "Helm release name for the Karpenter provider controller."
  type        = string
  default     = "karpenter-provider-hetzner"
  nullable    = false
}

variable "namespace" {
  description = "Kubernetes namespace the Karpenter provider controller is installed into."
  type        = string
  default     = "karpenter"
  nullable    = false
}

variable "create_namespace" {
  description = "Whether to create the target namespace if it does not already exist."
  type        = bool
  default     = true
  nullable    = false
}

variable "helm_repository" {
  description = "Helm/OCI repository hosting the karpenter-provider-hetzner chart."
  type        = string
  default     = "oci://ghcr.io/paperclipinc/charts"
  nullable    = false
}

variable "helm_chart" {
  description = "Helm chart name for the Karpenter provider controller."
  type        = string
  default     = "karpenter-provider-hetzner"
  nullable    = false
}

variable "chart_version" {
  description = "karpenter-provider-hetzner Helm chart version to install. Required: there is intentionally no default, so upgrading the chart is always an explicit, reviewed change in env.hcl rather than an implicit module upgrade."
  type        = string
}

variable "hcloud_token_secret_name" {
  description = "Name of the Kubernetes Secret, created by this module in the release namespace, holding the Hetzner Cloud API token consumed by the controller."
  type        = string
  default     = "karpenter-hcloud-token"
  nullable    = false
}

