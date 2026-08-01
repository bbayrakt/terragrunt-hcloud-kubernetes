# Gateway API Module

This Terraform module deploys the Gateway API configuration for Cilium with cert-manager integration for automatic TLS certificate management via Let's Encrypt.

## Features

- **Kubernetes Gateway Resource**: Creates a Cilium-based Gateway with Hetzner Cloud Load Balancer integration
- **Cert-Manager Issuer**: Deploys a Let's Encrypt ACME Issuer with HTTP-01 challenge solver using Gateway API
- **HTTPRoutes**: Manages HTTPRoute resources for routing traffic to your services
- **Flexible Configuration**: Highly configurable listeners, routes, and load balancer settings

## Prerequisites

1. **Kubernetes Cluster**: Must have the kubernetes-cluster module deployed first
2. **Cert-Manager**: Should be enabled in the kubernetes-cluster module (`cert_manager_enabled = true`)
3. **Cilium Gateway API**: Should be enabled in the kubernetes-cluster module (`cilium_gateway_api_enabled = true`)
4. **Terraform Provider**: Kubernetes provider >= 2.23

## Module Dependencies

This module depends on the `kubernetes-cluster` module. Ensure it's deployed before applying this module:

```bash
# Apply kubernetes-cluster first
cd environments/<env>/kubernetes-cluster
terragrunt apply

# Then apply gateway-api
cd ../gateway-api
terragrunt apply
```

## Configuration

### Required Secrets (in `secrets.yaml`)

```yaml
acme_email: "admin@example.com"              # Email for Let's Encrypt ACME account
gateway_api_lb_name: "k8s-gateway"          # Hetzner Load Balancer name
gateway_api_domain: "example.com"           # Primary domain for the gateway
```

### Example Environment Configuration (env.hcl)

```terraform
gateway_api_lb_name     = local.secrets.gateway_api_lb_name
gateway_api_lb_location = "nbg1"
gateway_api_lb_type     = "lb11"

gateway_api_listeners = [
  {
    name     = "https-example"
    hostname = local.secrets.gateway_api_domain
    port     = 443
    protocol = "HTTPS"
    tls = {
      mode = "Terminate"
      certificateRefs = [
        {
          name  = "example-tls"
          kind  = "Secret"
          group = ""
        }
      ]
    }
  },
  {
    name     = "http-example"
    hostname = local.secrets.gateway_api_domain
    port     = 80
    protocol = "HTTP"
  }
]

gateway_api_http_routes = {
  "example-https" = {
    name         = "example"
    namespace    = "default"
    section_name = "https-example"
    hostnames    = [local.secrets.gateway_api_domain]
    rules = [
      {
        backendRefs = [
          {
            name = "example-service"
            port = 80
          }
        ]
      }
    ]
  }
}
```

## Adding Multiple Domains

To add multiple domains/listeners:

```terraform
gateway_api_listeners = [
  {
    name     = "https-domain1"
    hostname = "domain1.com"
    port     = 443
    protocol = "HTTPS"
    tls = {
      mode = "Terminate"
      certificateRefs = [
        {
          name  = "domain1-tls"
          kind  = "Secret"
        }
      ]
    }
  },
  {
    name     = "https-domain2"
    hostname = "domain2.com"
    port     = 443
    protocol = "HTTPS"
    tls = {
      mode = "Terminate"
      certificateRefs = [
        {
          name  = "domain2-tls"
          kind  = "Secret"
        }
      ]
    }
  },
  # HTTP listeners for redirects
  {
    name     = "http-domain1"
    hostname = "domain1.com"
    port     = 80
    protocol = "HTTP"
  },
  {
    name     = "http-domain2"
    hostname = "domain2.com"
    port     = 80
    protocol = "HTTP"
  }
]

gateway_api_http_routes = {
  "domain1-https" = {
    name         = "domain1"
    namespace    = "default"
    section_name = "https-domain1"
    hostnames    = ["domain1.com"]
    rules = [
      {
        backendRefs = [{ name = "service1", port = 80 }]
      }
    ]
  },
  "domain2-https" = {
    name         = "domain2"
    namespace    = "default"
    section_name = "https-domain2"
    hostnames    = ["domain2.com"]
    rules = [
      {
        backendRefs = [{ name = "service2", port = 80 }]
      }
    ]
  },
  "domain1-redirect" = {
    name         = "domain1-redirect"
    namespace    = "ingress"
    section_name = "http-domain1"
    hostnames    = ["domain1.com"]
    rules = [
      {
        filters = [
          {
            type = "RequestRedirect"
            requestRedirect = {
              scheme     = "https"
              statusCode = 301
            }
          }
        ]
      }
    ]
  }
}
```

## Outputs

The module provides the following outputs:

- `namespace_name`: Name of the ingress namespace
- `issuer_name`: Name of the cert-manager Issuer
- `gateway_name`: Name of the Cilium Gateway
- `http_routes`: Map of created HTTPRoute resources

## Certificate Validation

Certificates are automatically validated using the HTTP-01 challenge through the Gateway API. The process:

1. Cert-manager creates an HTTPRoute with `/.well-known/acme-challenge/` path
2. Let's Encrypt validates the domain
3. Certificate is issued and stored in a Secret
4. The Gateway TLS listeners reference these Secrets

## Networking

The module creates resources in the following namespaces:

- **ingress**: Gateway and Issuer resources (created by module)
- **Custom namespaces**: HTTPRoute resources can be created in any namespace and reference the Gateway in the ingress namespace

## Hetzner Load Balancer Configuration

Configure load balancer settings via variables:

- `lb_name`: Name visible in Hetzner Cloud Console
- `lb_location`: Hetzner location (e.g., "nbg1", "ash", "hel1")
- `lb_type`: Load balancer type ("lb11", "lb21", "lb31")
- `lb_uses_proxyprotocol`: Enable PROXY protocol (useful for preserving client IPs)

## Troubleshooting

### Certificate Not Issuing

1. Check issuer status:
   ```bash
   kubectl describe issuer letsencrypt-http01 -n ingress
   ```

2. Check cert-manager logs:
   ```bash
   kubectl logs -n cert-manager deploy/cert-manager -f
   ```

3. Verify Gateway is ready:
   ```bash
   kubectl get gateway -n ingress
   kubectl describe gateway cilium-gateway -n ingress
   ```

### HTTPRoute Not Working

1. Check HTTPRoute status:
   ```bash
   kubectl get httproute -A
   kubectl describe httproute <route-name> -n <namespace>
   ```

2. Verify Gateway listeners match section names
3. Ensure backend services exist and are accessible

### Load Balancer Not Responding

1. Check load balancer in Hetzner Cloud Console
2. Verify firewall rules allow ports 80 and 443
3. Check Gateway infrastructure annotations match your setup

## References

- [Gateway API Documentation](https://gateway-api.sigs.k8s.io/)
- [Cilium Gateway API](https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/)
- [Cert-Manager Documentation](https://cert-manager.io/docs/)
- [Let's Encrypt](https://letsencrypt.org/)
