resource "kubernetes_namespace_v1" "ingress" {
  metadata {
    name = var.namespace
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }
}

# Cloudflare API token secret for cert-manager DNS-01 challenges
resource "kubernetes_secret_v1" "cloudflare_api_token_certmanager" {
  metadata {
    name      = "cloudflare-api-token"
    namespace = kubernetes_namespace_v1.ingress.metadata[0].name
  }

  type = "Opaque"

  data = {
    api-token = var.cloudflare_api_token
  }

  depends_on = [kubernetes_namespace_v1.ingress]
}

# Let's Encrypt ACME Issuer with Cloudflare DNS-01 challenge
resource "kubernetes_manifest" "letsencrypt_issuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Issuer"
    metadata = {
      name      = var.issuer_name
      namespace = kubernetes_namespace_v1.ingress.metadata[0].name
    }
    spec = {
      acme = {
        email  = var.acme_email
        server = var.acme_server
        privateKeySecretRef = {
          name = "${var.issuer_name}-key"
        }
        solvers = [
          {
            dns01 = {
              cloudflare = {
                apiTokenSecretRef = {
                  name = kubernetes_secret_v1.cloudflare_api_token_certmanager.metadata[0].name
                  key  = "api-token"
                }
              }
            }
          }
        ]
      }
    }
  }

  depends_on = [kubernetes_namespace_v1.ingress, kubernetes_secret_v1.cloudflare_api_token_certmanager]
}

# Cilium Gateway
resource "kubernetes_manifest" "cilium_gateway" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name      = var.gateway_name
      namespace = kubernetes_namespace_v1.ingress.metadata[0].name
      annotations = {
        "cert-manager.io/issuer" = var.issuer_name
      }
    }
    spec = {
      gatewayClassName = "cilium"
      infrastructure = {
        annotations = {
          "load-balancer.hetzner.cloud/name"              = var.lb_name
          "load-balancer.hetzner.cloud/location"          = var.lb_location
          "load-balancer.hetzner.cloud/type"              = var.lb_type
          "load-balancer.hetzner.cloud/uses-proxyprotocol" = tostring(var.lb_uses_proxyprotocol)
        }
      }
      listeners = [
        for listener in var.gateway_listeners : merge(
          {
            name     = listener.name
            hostname = listener.hostname
            port     = listener.port
            protocol = listener.protocol
          },
          lookup(listener, "allowedRoutes", null) != null ? {
            allowedRoutes = listener.allowedRoutes
          } : {},
          listener.protocol == "HTTPS" && lookup(listener, "tls", null) != null ? {
            tls = {
              mode = listener.tls.mode
              certificateRefs = [
                for ref in listener.tls.certificateRefs : {
                  name  = ref.name
                  kind  = lookup(ref, "kind", "Secret")
                  group = lookup(ref, "group", "")
                }
              ]
            }
          } : {}
        )
      ]
    }
  }

  depends_on = [kubernetes_namespace_v1.ingress]
}

# HTTP Routes
resource "kubernetes_manifest" "http_routes" {
  for_each = var.http_routes

  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = each.value.name
      namespace = each.value.namespace
    }
    spec = {
      parentRefs = [
        {
          name      = var.gateway_name
          namespace = kubernetes_namespace_v1.ingress.metadata[0].name
          sectionName = each.value.section_name
        }
      ]
      hostnames = each.value.hostnames
      rules     = each.value.rules
    }
  }

  computed_fields = [
    "spec.rules",
  ]

  depends_on = [kubernetes_manifest.cilium_gateway]
}

