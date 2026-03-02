# Staging Environment Configuration
# This file contains all input variables for all modules in the staging environment

locals {
  environment_name          = "staging"
  kubernetes_module_version = "3.23.0"
  secrets                   = yamldecode(sops_decrypt_file(find_in_parent_folders("secrets.yaml")))
  base_domain               = local.secrets.gateway_api_domain
  wildcard_domain           = "*.${local.environment_name}.${local.base_domain}"
}

inputs = {
  # Kubernetes Cluster Configuration

  cluster_name = "k8s-staging"
  hcloud_token = local.secrets.hcloud_token

  cert_manager_enabled = true

  cilium_encryption_enabled = true
  cilium_encryption_type    = "ipsec"

  cilium_gateway_api_enabled                = true
  cilium_gateway_api_proxy_protocol_enabled = false # Disabled due to IPv6 bug: https://github.com/cilium/cilium/issues/42950

  external_dns_enabled      = true
  external_dns_version      = "1.20.0"
  external_dns_provider     = "cloudflare"
  external_dns_cluster_name = "k8s-staging"
  cloudflare_api_token      = local.secrets.cloudflare_api_token

  talos_backup_s3_enabled    = true
  talos_backup_s3_region     = "us-east-1"
  talos_backup_s3_endpoint   = local.secrets.seaweedfs_endpoint
  talos_backup_s3_bucket     = "talos-backup"
  talos_backup_s3_path_style = false
  talos_backup_s3_access_key = local.secrets.seaweedfs_access_key
  talos_backup_s3_secret_key = local.secrets.seaweedfs_secret_key

  cluster_delete_protection = false

  control_plane_nodepools = [
    {
      name     = "control"
      type     = "cx23"
      location = "fsn1"
      count    = 1
    }
  ]

  worker_nodepools = [
    {
      name     = "worker"
      type     = "cx33"
      location = "fsn1"
      count    = 2
    }
  ]

  cluster_autoscaler_nodepools = [
    {
      name     = "autoscaler"
      type     = "cx33"
      location = "fsn1"
      min      = 0
      max      = 4
      labels   = { "autoscaler-node" = "true" }
    }
  ]

  # Gateway API Configuration

  lb_name               = local.secrets.gateway_api_lb_name
  lb_location           = "fsn1"
  lb_type               = "lb11"
  lb_uses_proxyprotocol = false

  gateway_listeners = [
    {
      name     = "https-wildcard"
      hostname = local.wildcard_domain
      port     = 443
      protocol = "HTTPS"
      allowedRoutes = {
        namespaces = {
          from = "All"
        }
      }
      tls = {
        mode = "Terminate"
        certificateRefs = [
          {
            name  = "wildcard-tls"
            kind  = "Secret"
            group = ""
          }
        ]
      }
    },
    {
      name     = "http-wildcard"
      hostname = local.wildcard_domain
      port     = 80
      protocol = "HTTP"
      allowedRoutes = {
        namespaces = {
          from = "All"
        }
      }
    }
  ]

  # HTTPRoutes - wildcard HTTP to HTTPS redirect
  http_routes = {
    "wildcard-redirect" = {
      name         = "wildcard-redirect"
      namespace    = "ingress"
      section_name = "http-wildcard"
      hostnames    = [local.wildcard_domain]
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

  # Helm Chart Secrets

  helm_secrets = {
    cloudflare-api-key = {
      name             = "cloudflare-api-key"
      namespace        = "kube-system"
      create_namespace = false
      data = {
        apiToken = local.secrets.cloudflare_api_token
      }
    }

    github-arc-pat = {
      name             = "github-arc-pat"
      namespace        = "arc-runners"
      create_namespace = true
      data = {
        github_token = local.secrets.github_token
      }
    }
  }

  # Helm Charts

  helm_charts = {
    external-dns = {
      repository   = "https://kubernetes-sigs.github.io/external-dns/"
      chart        = "external-dns"
      version      = "1.20.0"
      namespace    = "kube-system"
      release_name = "external-dns"
      manage_crds  = true
      install      = true
      values = {
        provider = {
          name = "cloudflare"
        }
        policy     = "sync"
        registry   = "txt"
        txtOwnerId = "k8s-staging"
        sources    = ["gateway-httproute"]
        env = [
          {
            name = "CF_API_TOKEN"
            valueFrom = {
              secretKeyRef = {
                name = "cloudflare-api-key"
                key  = "apiToken"
              }
            }
          }
        ]
        rbac = {
          create = true
        }
        service = {
          type = "ClusterIP"
        }
        logLevel = "info"
      }
    }

    gha-runner-scale-set-controller = {
      repository   = "oci://ghcr.io/actions/actions-runner-controller-charts"
      chart        = "gha-runner-scale-set-controller"
      version      = "0.13.1"
      namespace    = "arc-systems"
      release_name = "gha-runner-scale-set-controller"
      manage_crds  = true
      install      = true
      values       = {}
    }

    gha-runner-scale-set = {
      repository   = "oci://ghcr.io/actions/actions-runner-controller-charts"
      chart        = "gha-runner-scale-set"
      version      = "0.13.1"
      namespace    = "arc-runners"
      release_name = "gha-runner-scale-set"
      manage_crds  = false
      install      = true
      priority     = 2
      values = {
        githubConfigUrl    = local.secrets.github_config_url
        githubConfigSecret = "github-arc-pat"
        runnerGroup        = try(local.secrets.github_runner_group, "Default")
        minRunners         = 1
      }
    }

    argocd = {
      repository   = "https://argoproj.github.io/argo-helm"
      chart        = "argo-cd"
      version      = "9.4.5"
      namespace    = "argocd"
      release_name = "argocd"
      manage_crds  = false
      install      = true
      values = {
        global = {
          domain = "argocd.${local.environment_name}.${local.base_domain}"
        }
        configs = {
          params = {
            "server.insecure" = true
          }
        }
        server = {
          service = {
            type = "ClusterIP"
          }
          httproute = {
            enabled   = true
            hostnames = ["argocd.${local.environment_name}.${local.base_domain}"]
            parentRefs = [
              {
                name        = "cilium-gateway"
                namespace   = "ingress"
                sectionName = "https-wildcard"
              }
            ]
          }
        }
      }
    }
  }
}
