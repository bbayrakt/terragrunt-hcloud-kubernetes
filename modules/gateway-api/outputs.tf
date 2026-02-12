output "namespace_name" {
  description = "Name of the ingress namespace"
  value       = kubernetes_namespace_v1.ingress.metadata[0].name
}

output "issuer_name" {
  description = "Name of the cert-manager Issuer"
  value       = kubernetes_manifest.letsencrypt_issuer.manifest.metadata.name
}

output "gateway_name" {
  description = "Name of the Cilium Gateway"
  value       = kubernetes_manifest.cilium_gateway.manifest.metadata.name
}

output "http_routes" {
  description = "Created HTTPRoute resources"
  value       = {
    for name, route in kubernetes_manifest.http_routes : name => {
      name      = route.manifest.metadata.name
      namespace = route.manifest.metadata.namespace
    }
  }
}

output "external_dns_enabled" {
  description = "Whether External DNS is enabled"
  value       = var.external_dns_enabled
}

output "external_dns_release_name" {
  description = "Name of the External DNS Helm release"
  value       = var.external_dns_enabled ? helm_release.external_dns[0].name : null
}

output "external_dns_namespace" {
  description = "Namespace where External DNS is deployed"
  value       = var.external_dns_namespace
}
