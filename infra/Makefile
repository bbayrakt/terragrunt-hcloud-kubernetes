.PHONY: help init plan apply destroy clean setup edit-secrets view-secrets sync-k8s-wrapper

# Default target
help:
	@echo "Terragrunt + SOPS Makefile Commands"
	@echo "===================================="
	@echo ""
	@echo "Setup:"
	@echo "  make setup          - Run initial setup script"
	@echo "  make init           - Initialize Terragrunt/Terraform"
	@echo ""
	@echo "Secrets Management:"
	@echo "  make edit-secrets   - Edit encrypted secrets with SOPS"
	@echo "  make view-secrets   - View decrypted secrets"
	@echo ""
	@echo "Infrastructure:"
	@echo "  make plan           - Plan infrastructure changes"
	@echo "  make apply          - Apply infrastructure changes"
	@echo "  make destroy        - Destroy infrastructure"
	@echo ""
	@echo "Maintenance:"
	@echo "  make clean          - Clean Terragrunt/Terraform cache"
	@echo "  make validate       - Validate Terragrunt configuration"
	@echo ""
	@echo "Environment-specific (set ENV=production or ENV=staging):"
	@echo "  make plan ENV=production"
	@echo "  make apply ENV=production"

ENV ?= production
MODULE ?= kubernetes-cluster

# Initial setup
setup:
	@./setup.sh

# Initialize Terragrunt
init:
	@echo "Initializing Terragrunt in environments/$(ENV)/$(MODULE)..."
	@cd environments/$(ENV)/$(MODULE) && terragrunt init

# Plan changes
plan:
	@echo "Planning changes in environments/$(ENV)/$(MODULE)..."
	@cd environments/$(ENV)/$(MODULE) && terragrunt plan

# Apply changes
apply:
	@echo "Applying changes in environments/$(ENV)/$(MODULE)..."
	@cd environments/$(ENV)/$(MODULE) && terragrunt apply

# Destroy infrastructure
destroy:
	@echo "Destroying infrastructure in environments/$(ENV)/$(MODULE)..."
	@cd environments/$(ENV)/$(MODULE) && terragrunt destroy

# Clean cache
clean:
	@echo "Cleaning Terragrunt and Terraform cache..."
	@find . -type d -name ".terragrunt-cache" -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name ".terraform-state" -exec rm -rf {} + 2>/dev/null || true
	@echo "Cache cleaned!"

# Edit secrets
edit-secrets:
	@if [ ! -f "secrets.yaml" ]; then \
		echo "secrets.yaml not found. Creating from template..."; \
		cp secrets.yaml.example secrets.yaml; \
	fi
	@sops secrets.yaml

# View secrets (decrypted)
view-secrets:
	@sops -d secrets.yaml

# Validate configuration
validate:
	@echo "Validating Terragrunt configuration..."
	@cd environments/$(ENV)/$(MODULE) && terragrunt validate

# Run all for an environment
run-all-plan:
	@echo "Planning all modules in environments/$(ENV)..."
	@cd environments/$(ENV) && terragrunt run-all plan

run-all-apply:
	@echo "Applying all modules in environments/$(ENV)..."
	@cd environments/$(ENV) && terragrunt run-all apply

run-all-destroy:
	@echo "Destroying all modules in environments/$(ENV)..."
	@cd environments/$(ENV) && terragrunt run-all destroy

# Initialize all modules
init-all:
	@echo "Initializing all modules in environments/$(ENV)..."
	@cd environments/$(ENV) && terragrunt run-all init

# Show what would be generated
show-config:
	@echo "Showing Terragrunt configuration for environments/$(ENV)/$(MODULE)..."
	@cd environments/$(ENV)/$(MODULE) && terragrunt run --terragrunt-info

# Sync kubernetes wrapper module with upstream module inputs
sync-k8s-wrapper:
	@echo "Syncing modules/kubernetes-cluster wrapper from upstream module..."
	@if [ -n "$(VERSION)" ]; then \
		python scripts/sync_kubernetes_wrapper.py --version "$(VERSION)"; \
	else \
		python scripts/sync_kubernetes_wrapper.py; \
	fi
