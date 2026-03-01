terraform {
  backend "s3" {
    access_key                  = "<your-seaweedfs-access-key>"
    bucket                      = "terragrunt-hcloud-kubernetes"
    endpoint                    = "http://localhost:8333"  # Update with your SeaweedFS endpoint
    force_path_style            = true
    key                         = "environments/staging/kubernetes-cluster/terraform.tfstate"
    region                      = "us-east-1"
    secret_key                  = "<your-seaweedfs-secret-key>"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
  }
}
