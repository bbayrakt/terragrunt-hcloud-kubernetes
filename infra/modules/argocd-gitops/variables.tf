variable "gitops_repo_url" {
  description = "URL of the GitOps content repository — either this repo's own URL (self-referencing monorepo) or a separate, dedicated GitOps repository. Both topologies are equally supported; only the value differs. Use an SSH URL (git@...) with gitops_repo_ssh_private_key, or an HTTPS URL with gitops_repo_username/gitops_repo_password (or neither, for a public HTTPS repository)."
  type        = string
}

variable "gitops_repo_ssh_private_key" {
  description = "SSH deploy key (read-only) used by ArgoCD to pull the GitOps repository over SSH. Leave null (the default) when using HTTPS auth (gitops_repo_username/gitops_repo_password) or a public HTTPS repository with no credentials."
  type        = string
  sensitive   = true
  default     = null
}

variable "gitops_repo_username" {
  description = "Username for HTTPS credential auth against the GitOps repository (e.g. paired with a personal access token in gitops_repo_password). Ignored when gitops_repo_ssh_private_key is set, since SSH auth always uses the \"git\" username by convention. Leave null for a public HTTPS repository with no credentials."
  type        = string
  default     = null
}

variable "gitops_repo_password" {
  description = "Password or personal access token for HTTPS credential auth against the GitOps repository, paired with gitops_repo_username. Ignored when gitops_repo_ssh_private_key is set. Leave null for a public HTTPS repository with no credentials."
  type        = string
  sensitive   = true
  default     = null
}

variable "gitops_apps_path" {
  description = "Path (relative to the GitOps repo root) whose subdirectories the `apps`-tier ApplicationSet's git directory generator watches"
  type        = string
  default     = "apps"

  validation {
    condition     = var.gitops_apps_path != "" && var.gitops_apps_path != "." && !startswith(var.gitops_apps_path, "/") && !endswith(var.gitops_apps_path, "/")
    error_message = "gitops_apps_path must be a non-empty relative path segment (not \"\", not \".\", no leading or trailing slash) -- a degenerate value here would widen the apps-tier ApplicationSet's directory-generator match beyond the intended subtree."
  }
}

variable "gitops_platform_path" {
  description = "Path (relative to the GitOps repo root) whose subdirectories the `platform`-tier ApplicationSet's git directory generator watches"
  type        = string
  default     = "platform"

  validation {
    condition     = var.gitops_platform_path != "" && var.gitops_platform_path != "." && !startswith(var.gitops_platform_path, "/") && !endswith(var.gitops_platform_path, "/")
    error_message = "gitops_platform_path must be a non-empty relative path segment (not \"\", not \".\", no leading or trailing slash) -- a degenerate value here would widen the platform-tier ApplicationSet's directory-generator match beyond the intended subtree."
  }
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
  # `sealed-secrets` (not `kube-system`) -- found by ce-code-review: since the ApplicationSet
  # template derives destination.namespace from the GitOps repo's directory basename
  # ({{path.basename}}), each app's directory name IS its target namespace. A dedicated
  # namespace also avoids depositing the Sealed Secrets controller into kube-system.
  default = ["arc-systems", "sealed-secrets"]
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
    # Found via live apply (U5): CreateNamespace=true's PreSync namespace-creation task is
    # itself a cluster-scoped resource op subject to this whitelist -- omitting Namespace here
    # made every platform-tier app's first sync fail with "resource :Namespace is not permitted
    # in project platform", since ArgoCD denies any cluster-scoped kind absent from the
    # whitelist by default. Safe to allow broadly: an Application's destination.namespace is
    # already validated against platform_destination_namespaces at the AppProject level, so this
    # can only ever create one of those pre-approved namespaces, never an arbitrary one.
    { group = "", kind = "Namespace" },
  ]
}
