# Staging Environment Configuration
# This file contains all input variables for all modules in the staging environment

locals {
  environment_name = "staging"
  secrets          = yamldecode(sops_decrypt_file(find_in_parent_folders("secrets.yaml")))
}

inputs = {
  # Kubernetes Cluster Configuration
  
  # See https://github.com/hcloud-k8s/terraform-hcloud-kubernetes/releases
  terraform_hcloud_kubernetes_module_version = "3.21.3"

  cluster_name = "k8s-staging"
  hcloud_token = local.secrets.hcloud_token

  # Enable Cert Manager
  cert_manager_enabled = true

  # Cilium Transparent Encryption
  cilium_encryption_enabled = true
  cilium_encryption_type    = "ipsec"

  # Cilium Gateway API
  cilium_gateway_api_enabled                = true
  cilium_gateway_api_proxy_protocol_enabled = false # Disabled due to IPv6 bug: https://github.com/cilium/cilium/issues/42950

  # Talos Backup
  talos_backup_s3_enabled    = true
  talos_backup_s3_region     = "us-east-1"
  talos_backup_s3_endpoint   = local.secrets.seaweedfs_endpoint
  talos_backup_s3_bucket     = "talos-backup"
  talos_backup_s3_path_style = false
  talos_backup_s3_access_key = local.secrets.seaweedfs_access_key
  talos_backup_s3_secret_key = local.secrets.seaweedfs_secret_key

  cluster_delete_protection = false

  # Smaller node pools for staging
  control_plane_nodepools = [
    {
      name     = "control"
      type     = "cx23"
      location = "nbg1"
      count    = 1
    }
  ]

  worker_nodepools = [
    {
      name     = "worker"
      type     = "cx33"
      location = "nbg1"
      count    = 2
    }
  ]

  cluster_autoscaler_nodepools = [
    {
      name     = "autoscaler"
      type     = "cx33"
      location = "nbg1"
      min      = 0
      max      = 4
      labels   = { "autoscaler-node" = "true" }
    }
  ]

  # ==================== Gateway API Configuration ====================
  
  lb_name               = local.secrets.gateway_api_lb_name
  lb_location           = "nbg1"
  lb_type               = "lb11"
  lb_uses_proxyprotocol = false # Disable proxy protocol for now

  # Gateway Listeners - configure for your domains
  gateway_listeners = [
    {
      name     = "https-example"
      hostname = local.secrets.gateway_api_domain
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
      allowedRoutes = {
        namespaces = {
          from = "All"
        }
      }
    }
  ]

  # HTTPRoutes - configure your service routes
  http_routes = {
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
    "example-redirect" = {
      name         = "example-redirect"
      namespace    = "default"
      section_name = "http-example"
      hostnames    = [local.secrets.gateway_api_domain]
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
      manage_crds  = false
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
