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

variable "locations" {
  description = "Hetzner location(s) Karpenter may provision workers in. Applied to both the HCloudNodeClass spec.locations and the NodePool's topology.kubernetes.io/zone requirement (operator In), so listing multiple locations here lets Karpenter spread/bin-pack workers across all of them."
  type        = list(string)
  default     = ["fsn1"]
  nullable    = false
}

variable "architectures" {
  description = "CPU architectures Karpenter may provision for the NodePool (kubernetes.io/arch requirement, operator In). Default is amd64-only since Hetzner Cloud does not yet offer arm64 server types; override if/when that changes or to restrict further."
  type        = list(string)
  default     = ["amd64"]
  nullable    = false
}

variable "server_types" {
  description = "Hetzner server types Karpenter may provision for the NodePool (karpenter.sh/v1 NodePool node.kubernetes.io/instance-type requirement, operator In). Karpenter bin-packs the cheapest type from this list that fits a pending pod. Each type's server family (e.g. cx, cpx) is implied by the type itself, so no separate family requirement is needed."
  type        = list(string)
  default     = ["cpx32"]
  nullable    = false
}

variable "worker_cpu_limit" {
  description = "Maximum total CPU Karpenter may provision for the staging pool."
  type        = string
  default     = "16"
  nullable    = false
}

variable "public_ipv4_enabled" {
  description = "Whether Karpenter workers receive public IPv4 addresses."
  type        = bool
  default     = true
  nullable    = false
}

variable "public_ipv6_enabled" {
  description = "Whether Karpenter workers receive public IPv6 addresses."
  type        = bool
  default     = true
  nullable    = false
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

variable "environment" {
  description = "Environment name used to label Karpenter-managed resources (e.g. the HCloudNodeClass). Required so labels are never silently hardcoded to one environment."
  type        = string
}

variable "nodeclass_name" {
  description = "Name of the managed HCloudNodeClass."
  type        = string
  default     = "talos-default"
  nullable    = false
}

variable "nodeclass_labels" {
  description = "Additional or overriding labels merged onto the HCloudNodeClass spec.labels, in addition to the module's cluster/managed-by/environment labels."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "nodeclass_spec_overrides" {
  description = "Arbitrary overrides merged (shallow, top-level) over the computed HCloudNodeClass spec. Use this to override or add any field not already exposed as a dedicated variable (e.g. firewallIDs, sshKeyIDs, userData)."
  type        = any
  default     = {}
  nullable    = false
}

variable "nodepool_name" {
  description = "Name of the managed NodePool."
  type        = string
  default     = "default"
  nullable    = false
}

variable "nodepool_template_labels" {
  description = "Additional or overriding labels merged onto the NodePool template.metadata.labels, in addition to the module's workload-class label."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "nodepool_spec_overrides" {
  description = <<-EOT
    Arbitrary overrides merged (shallow, top-level) over the computed NodePool
    spec. Use this to override or add any field not already exposed as a
    dedicated variable (e.g. taints, weight, additional requirements, or the
    default disruption policy).

    Note: the merge is shallow at the top level of spec, so supplying a key
    here (e.g. "disruption") fully replaces the module's computed value for
    that key rather than deep-merging into it. Example, to relax the default
    consolidation policy:

      nodepool_spec_overrides = {
        disruption = {
          consolidationPolicy = "WhenEmpty"
          consolidateAfter    = "5m"
        }
      }
  EOT
  type        = any
  default     = {}
  nullable    = false
}

