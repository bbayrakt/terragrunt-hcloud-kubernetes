# Staging Environment Configuration
# This file contains all input variables for all modules in the staging environment

locals {
  environment_name          = "staging"
  kubernetes_module_version = "5.3.0"
  secrets                   = yamldecode(sops_decrypt_file(find_in_parent_folders("secrets.yaml")))
  base_domain               = local.secrets.gateway_api_domain
  wildcard_domain           = "*.${local.environment_name}.${local.base_domain}"
  cluster_name              = "k8s-staging"
}

inputs = {
  # Kubernetes Cluster Configuration

  cluster_name = local.cluster_name
  hcloud_token = local.secrets.hcloud_token

  # ArgoCD GitOps repository (registered via the argocd-gitops stack's argocd_repository resource)
  gitops_repo_url             = local.secrets.gitops_repo_url
  gitops_repo_ssh_private_key = local.secrets.gitops_repo_ssh_private_key

  # Top-level directory (relative to gitops_repo_url) each tier's ApplicationSet watches --
  # defaults match the layout this repo actually uses (apps/, platform/ at the true repo root).
  gitops_apps_path     = "apps"
  gitops_platform_path = "platform"

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

  karpenter_chart_version = "2.0.0"

  karpenter_locations      = ["fsn1"]
  karpenter_nodeclass_name = "talos-default"
  #   karpenter_nodeclass_labels = { team = "platform", tier = "worker" }
  karpenter_nodeclass_labels = {}
  #   karpenter_nodeclass_spec_overrides = { firewallIDs = ["123456"] }
  karpenter_nodeclass_spec_overrides = {}
  karpenter_nodepool_name            = "staging-cpx"
  karpenter_server_types = [
    "cx23",
    "cx33",
    "cx43",
    "cpx22",
    "cpx32",
  ]
  karpenter_worker_cpu_limit = "16"
  #   karpenter_nodepool_template_labels = { "workload-class" = "batch" }
  karpenter_nodepool_template_labels = {}
  #   karpenter_nodepool_spec_overrides = {
  #     disruption = {
  #       consolidationPolicy = "WhenEmpty"
  #       consolidateAfter    = "5m"
  #     }
  #   }
  karpenter_nodepool_spec_overrides = {}

  control_plane_nodepools = [
    {
      name     = "control"
      type     = "cpx32"
      location = "fsn1"
      count    = 1
    }
  ]

  # A single static "system" worker hosts the Karpenter controller.
  # Its presence causes the upstream module to automatically taint the 
  # control plane with node-role.kubernetes.io/control-plane:NoSchedule 
  # (worker_sum > 0)
  worker_nodepools = [
    {
      name     = "system"
      type     = "cpx22"
      location = "fsn1"
      count    = 1
      labels = {
        "workload-class" = "worker"
      }
    }
  ]

  cluster_autoscaler_nodepools         = []
  cluster_autoscaler_discovery_enabled = false

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

    # Platform-tier AGE private key for KSOPS, mounted into argocd-repo-server (see the argocd
    # chart's `repoServer` values below). create_namespace = true: on a fresh cluster this secret
    # is created before the argocd Helm release itself creates the `argocd` namespace, so it must
    # ensure the namespace exists rather than assume it (found via live deploy validation --
    # assuming the chart "already creates it" was wrong for a first-time apply).
    platform-sops-age-key = {
      name             = "platform-sops-age-key"
      namespace        = "argocd"
      create_namespace = true
      data = {
        "keys.txt" = local.secrets.platform_sops_age_private_key
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

    argocd = {
      repository   = "https://argoproj.github.io/argo-helm"
      chart        = "argo-cd"
      version      = "9.4.5"
      namespace    = "argocd"
      release_name = "argocd"
      manage_crds  = false
      install      = true
      priority     = 3
      values = {
        global = {
          domain = "argocd.${local.environment_name}.${local.base_domain}"
        }
        configs = {
          params = {
            "server.insecure" = true
          }
          # KSOPS build option for platform-tier SOPS-encrypted secrets. --enable-alpha-plugins
          # and --enable-exec are both required (--enable-exec alone is easy to miss). NOT using
          # --enable-helm here -- platform-tier apps use ArgoCD's native multi-source Helm support,
          # not Kustomize helmCharts: inflation (see docs/plans/2026-07-30-001-feat-argocd-gitops-migration-plan.md,
          # Key Technical Decisions #10).
          cm = {
            "kustomize.buildOptions" = "--enable-alpha-plugins --enable-exec"
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
        # KSOPS init container + volumes on the repo-server, patched additively onto the existing
        # argocd release (no new Helm chart). Mounts the platform-sops-age-key Secret created above.
        repoServer = {
          volumes = [
            {
              name     = "custom-tools"
              emptyDir = {}
            },
            {
              name = "sops-age"
              secret = {
                secretName = "platform-sops-age-key"
              }
            }
          ]
          initContainers = [
            {
              name    = "install-ksops"
              image   = "viaductoss/ksops:v4.5.1"
              command = ["/usr/local/bin/ksops", "install", "--with-kustomize", "/custom-tools"]
              volumeMounts = [
                {
                  name      = "custom-tools"
                  mountPath = "/custom-tools"
                }
              ]
            }
          ]
          volumeMounts = [
            {
              name      = "custom-tools"
              mountPath = "/usr/local/bin/kustomize"
              subPath   = "kustomize"
            },
            {
              name      = "custom-tools"
              mountPath = "/usr/local/bin/ksops"
              subPath   = "ksops"
            },
            {
              name      = "sops-age"
              mountPath = "/sops/age"
              readOnly  = true
            }
          ]
          env = [
            {
              name  = "SOPS_AGE_KEY_FILE"
              value = "/sops/age/keys.txt"
            }
          ]
        }
      }
    }
  }
}
