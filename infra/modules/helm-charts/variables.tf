variable "charts" {
  description = "Unified Helm chart definitions for release installation"
  type        = any
}

variable "secrets" {
  description = "Kubernetes secrets to create before installing charts. Map of secret key => { name, namespace, data, type(optional) }"
  type        = any
  default     = {}
}
