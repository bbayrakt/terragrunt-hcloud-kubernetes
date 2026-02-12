variable "namespace" {
  description = "Kubernetes namespace for ingress resources"
  type        = string
  default     = "ingress"
}

variable "issuer_name" {
  description = "Name of the cert-manager Issuer"
  type        = string
  default     = "letsencrypt-http01"
}

variable "acme_email" {
  description = "Email address for Let's Encrypt ACME account"
  type        = string
  sensitive   = true
}

variable "acme_server" {
  description = "Let's Encrypt ACME server URL"
  type        = string
  default     = "https://acme-v02.api.letsencrypt.org/directory"
}

variable "gateway_name" {
  description = "Name of the Cilium Gateway"
  type        = string
  default     = "cilium-gateway"
}

variable "gateway_listeners" {
  description = "Gateway API listeners configuration"
  type = list(object({
    name           = string
    hostname       = string
    port           = number
    protocol       = string
    allowedRoutes  = optional(object({
      namespaces = optional(object({
        from = optional(string, "All")
      }))
    }))
    tls = optional(object({
      mode             = string
      certificateRefs  = list(object({
        name  = string
        kind  = optional(string, "Secret")
        group = optional(string, "")
      }))
    }))
  }))
}

variable "lb_name" {
  description = "Hetzner Load Balancer name"
  type        = string
}

variable "lb_location" {
  description = "Hetzner Load Balancer location"
  type        = string
  default     = "nbg1"
}

variable "lb_type" {
  description = "Hetzner Load Balancer type"
  type        = string
  default     = "lb11"
}

variable "lb_uses_proxyprotocol" {
  description = "Whether the load balancer uses PROXY protocol"
  type        = bool
  default     = true
}

variable "http_routes" {
  description = "HTTPRoute resources to create"
  type = map(object({
    name         = string
    namespace    = string
    section_name = string
    hostnames    = list(string)
    rules = list(object({
      matches = optional(list(object({
        path = optional(object({
          type  = optional(string, "PathPrefix")
          value = optional(string, "/")
        }))
      })))
      filters = optional(list(object({
        type            = string
        requestRedirect = optional(object({
          scheme     = optional(string)
          statusCode = optional(number)
        }))
      })))
      backendRefs = optional(list(object({
        name      = string
        port      = optional(number)
        weight    = optional(number)
        namespace = optional(string)
      })))
    }))
  }))
  default = {}
}

variable "external_dns_enabled" {
  description = "Enable External DNS for automatic DNS record management"
  type        = bool
  default     = true
}

variable "external_dns_namespace" {
  description = "Kubernetes namespace for External DNS"
  type        = string
  default     = "kube-system"
}

variable "external_dns_version" {
  description = "External DNS Helm chart version"
  type        = string
}

variable "external_dns_provider" {
  description = "DNS provider for External DNS (cloudflare, route53, etc.)"
  type        = string
  default     = "cloudflare"
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token for DNS management"
  type        = string
  sensitive   = true
}

variable "external_dns_cluster_name" {
  description = "Cluster name for External DNS (used for filtering)"
  type        = string
}

variable "external_dns_helm_values" {
  description = "Custom Helm values for External DNS"
  type        = any
  default     = {}
}
