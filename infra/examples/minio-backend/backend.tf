terraform {
  backend "s3" {
    access_key                  = "<your-minio-root-user>"
    bucket                      = "terragrunt-hcloud-kubernetes"
    endpoint                    = "http://localhost:9000"  # Update with your MinIO endpoint
    force_path_style            = true
    key                         = "environments/staging/kubernetes-cluster/terraform.tfstate"
    region                      = "us-east-1"
    secret_key                  = "<your-minio-root-password>"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
  }
}
