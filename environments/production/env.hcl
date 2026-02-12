# Production Environment Configuration
# This file contains all input variables for all modules in the production environment

locals {
  environment_name = "production"
  secrets          = yamldecode(sops_decrypt_file(find_in_parent_folders("secrets.yaml")))
}

inputs = {
  # Kubernetes Cluster Configuration

  # See https://github.com/hcloud-k8s/terraform-hcloud-kubernetes/releases
  terraform_hcloud_kubernetes_module_version = "3.21.3"

  cluster_name = "k8s-production"
  hcloud_token = local.secrets.hcloud_token

  # Enable Cert Manager
  cert_manager_enabled = true

  # Cilium Gateway API
  cilium_gateway_api_enabled = true

  # Talos Backup
  talos_backup_s3_enabled     = true
  talos_backup_s3_region      = "us-east-1"
  talos_backup_s3_endpoint    = local.secrets.minio_endpoint
  talos_backup_s3_bucket      = "talos-backup"
  talos_backup_s3_path_style  = false  # false for MinIO (S3-like endpoint), true for AWS S3
  talos_backup_s3_access_key  = local.secrets.minio_access_key
  talos_backup_s3_secret_key  = local.secrets.minio_secret_key

  cluster_delete_protection = true

  # At least 3 control plane nodes are recommended for production clusters for high availability
  control_plane_nodepools = [
    {
      name     = "control"
      type     = "cx33"
      location = "nbg1"
      count    = 3
    }
  ]

  worker_nodepools = [
    {
      name     = "worker"
      type     = "cx33"
      location = "nbg1"
      count    = 3
    }
  ]

  # ==================== Gateway API Configuration ====================
  
  lb_name     = local.secrets.gateway_api_lb_name
  lb_location = "nbg1"
  lb_type     = "lb11"

  # Gateway Listeners - configure for your domains
  gateway_listeners = [
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

  # ==================== External DNS Configuration ====================

  external_dns_enabled        = true
  external_dns_version        = "1.20.0"
  external_dns_provider       = "cloudflare"
  external_dns_cluster_name   = "k8s-production"
  cloudflare_api_token        = local.secrets.cloudflare_api_token
  external_dns_helm_values    = {}
}
