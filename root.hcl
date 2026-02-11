# Root Terragrunt configuration

locals {
  # Load environment-specific variables
  environment = path_relative_to_include() != "" ? split("/", path_relative_to_include())[1] : "unknown"
  
  # Load secrets from SOPS-encrypted file
  secrets = yamldecode(sops_decrypt_file(find_in_parent_folders("secrets.yaml", "secrets.yaml.example")))
}

# Configure remote state backend with HTTP backend
# eg. Lynx, GitLab, Terraform Cloud, etc. Adjust config as needed for your backend.
remote_state {
  backend = "s3"
  
  config = {
    bucket   = "terragrunt-hcloud-kubernetes"
    key      = "${path_relative_to_include()}/terraform.tfstate"
    region   = "us-east-1"  # Required but not used for MinIO
    
    endpoint = local.secrets.minio_endpoint
    
    # MinIO/S3-compatible settings
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true
    
    # Credentials from secrets.yaml
    access_key = local.secrets.minio_access_key
    secret_key = local.secrets.minio_secret_key
  }
  
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

# Common inputs to pass to all child modules
inputs = {
  # Add any common variables here
}
