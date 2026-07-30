variable "gitops_repo_url" {
  description = "SSH URL of the dedicated GitOps repository (e.g. git@github.com:org/gitops-repo.git)"
  type        = string
}

variable "gitops_repo_ssh_private_key" {
  description = "SSH deploy key (read-only) used by ArgoCD to pull the GitOps repository"
  type        = string
  sensitive   = true
}

variable "apps_destination_namespaces" {
  description = "Namespace allow-list for the `apps` AppProject's destinations"
  type        = list(string)
  default     = ["arc-runners"]
}

variable "apps_pod_security_level" {
  description = "Pod Security Standard level applied to `apps`-tier namespaces via managed_namespace_metadata (restricted or baseline)"
  type        = string
  default     = "restricted"
}

variable "platform_destination_namespaces" {
  description = "Namespace allow-list for the `platform` AppProject's destinations"
  type        = list(string)
  default     = ["arc-systems", "kube-system"]
}

variable "platform_cluster_resource_whitelist" {
  description = "Cluster-scoped group/kind pairs the `platform` AppProject is allowed to create"
  type = list(object({
    group = string
    kind  = string
  }))
  default = [
    { group = "apiextensions.k8s.io", kind = "CustomResourceDefinition" },
    { group = "rbac.authorization.k8s.io", kind = "ClusterRole" },
    { group = "rbac.authorization.k8s.io", kind = "ClusterRoleBinding" },
  ]
}
