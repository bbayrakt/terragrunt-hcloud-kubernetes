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
  backend = "http"
  
  config = {
    address        = format("%s/%s/state", local.secrets.terraform_backend_address, local.environment)
    lock_address   = format("%s/%s/lock", local.secrets.terraform_backend_lock_address, local.environment)
    unlock_address = format("%s/%s/unlock", local.secrets.terraform_backend_unlock_address, local.environment)
    username       = local.secrets.terraform_backend_username
    password       = local.secrets.terraform_backend_password
    lock_method    = "POST"
    unlock_method  = "POST"
  }
  
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

# Alternative: Uncomment to use local backend instead
# remote_state {
#   backend = "local"
#   
#   config = {
#     path = "${get_parent_terragrunt_dir()}/.terraform-state/${path_relative_to_include()}/terraform.tfstate"
#   }
#   
#   generate = {
#     path      = "backend.tf"
#     if_exists = "overwrite_terragrunt"
#   }
# }
#
# Alternative: Uncomment to use S3 backend
# remote_state {
#   backend = "s3"
#   
#   config = {
#     bucket         = "your-terraform-state-bucket"
#     key            = "${path_relative_to_include()}/terraform.tfstate"
#     region         = "us-east-1"
#     encrypt        = true
#     dynamodb_table = "terraform-locks"
#   }
# }

# Common inputs to pass to all child modules
inputs = {
  # Add any common variables here
}
