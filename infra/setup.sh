#!/bin/bash
# Terragrunt + SOPS Quick Setup Script

set -e

echo "🚀 Terragrunt + SOPS Setup Script"
echo "================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo "📋 Checking prerequisites..."
MISSING_DEPS=0

if ! command_exists terragrunt; then
    echo -e "${RED}✗${NC} Terragrunt not found"
    MISSING_DEPS=1
else
    echo -e "${GREEN}✓${NC} Terragrunt installed"
fi

if ! command_exists terraform; then
    echo -e "${RED}✗${NC} Terraform not found"
    MISSING_DEPS=1
else
    echo -e "${GREEN}✓${NC} Terraform installed"
fi

if ! command_exists sops; then
    echo -e "${RED}✗${NC} SOPS not found"
    MISSING_DEPS=1
else
    echo -e "${GREEN}✓${NC} SOPS installed"
fi

if ! command_exists age-keygen; then
    echo -e "${YELLOW}⚠${NC} Age not found (optional but recommended)"
else
    echo -e "${GREEN}✓${NC} Age installed"
fi

if [ $MISSING_DEPS -eq 1 ]; then
    echo ""
    echo -e "${RED}Missing required dependencies. Please install them and try again.${NC}"
    echo "See TERRAGRUNT_README.md for installation instructions."
    exit 1
fi

echo ""
echo "🔐 Setting up SOPS encryption..."

# Check if age key already exists
if [ -f "keys.txt" ]; then
    echo -e "${YELLOW}⚠${NC} Age keys file already exists at keys.txt"
    read -p "Do you want to generate a new key? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Skipping key generation."
    else
        mv keys.txt keys.txt.backup
        echo "Existing keys backed up to keys.txt.backup"
        age-keygen -o keys.txt
        echo -e "${GREEN}✓${NC} New age keys generated"
    fi
else
    if command_exists age-keygen; then
        age-keygen -o keys.txt
        echo -e "${GREEN}✓${NC} Age keys generated and saved to keys.txt"
        echo -e "${YELLOW}⚠${NC} IMPORTANT: Backup this file in a secure location!"
    else
        echo -e "${YELLOW}⚠${NC} Age not installed. Skipping key generation."
        echo "You'll need to manually configure SOPS with PGP or cloud KMS."
    fi
fi

# Extract public key and update .sops.yaml
if [ -f "keys.txt" ] && command_exists age-keygen; then
    PUBLIC_KEY=$(grep "public key:" keys.txt | awk '{print $4}')
    
    if [ -n "$PUBLIC_KEY" ]; then
        echo ""
        echo "Public key: $PUBLIC_KEY"
        
        # Update .sops.yaml with the actual public key
        sed -i.bak "s/age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx/$PUBLIC_KEY/" .sops.yaml
        echo -e "${GREEN}✓${NC} .sops.yaml updated with your public key"
    fi
fi

# Setup secrets file
echo ""
echo "📝 Setting up secrets file..."

if [ -f "secrets.yaml" ]; then
    echo -e "${YELLOW}⚠${NC} secrets.yaml already exists"
else
    cp secrets.yaml.example secrets.yaml
    echo -e "${GREEN}✓${NC} Created secrets.yaml from template"
    
    # Prompt for Hetzner token
    echo ""
    read -p "Enter your Hetzner Cloud API token (or press Enter to skip): " -s HCLOUD_TOKEN
    echo
    
    if [ -n "$HCLOUD_TOKEN" ]; then
        sed -i.bak "s/YOUR_HCLOUD_TOKEN_HERE/$HCLOUD_TOKEN/" secrets.yaml
        echo -e "${GREEN}✓${NC} Hetzner Cloud token added"
    fi
    
    # Encrypt the secrets file
    if [ -f "keys.txt" ]; then
        export SOPS_AGE_KEY_FILE="$(pwd)/keys.txt"
        sops -e -i secrets.yaml
        echo -e "${GREEN}✓${NC} secrets.yaml encrypted with SOPS"
    else
        echo -e "${YELLOW}⚠${NC} Secrets file created but not encrypted (no age keys found)"
        echo "Run 'sops -e -i secrets.yaml' after setting up encryption keys"
    fi
fi

# Setup environment variable
echo ""
echo "🔧 Setting up environment..."

if [ -f "keys.txt" ]; then
    export SOPS_AGE_KEY_FILE="$(pwd)/keys.txt"
    
    # Add to shell profile if not already there
    SHELL_RC=""
    if [ -n "$BASH_VERSION" ]; then
        SHELL_RC="$HOME/.bashrc"
    elif [ -n "$ZSH_VERSION" ]; then
        SHELL_RC="$HOME/.zshrc"
    fi
    
    if [ -n "$SHELL_RC" ] && [ -f "$SHELL_RC" ]; then
        if ! grep -q "SOPS_AGE_KEY_FILE" "$SHELL_RC"; then
            echo "" >> "$SHELL_RC"
            echo "# SOPS age key for Terragrunt" >> "$SHELL_RC"
            echo "export SOPS_AGE_KEY_FILE=\"$(pwd)/keys.txt\"" >> "$SHELL_RC"
            echo -e "${GREEN}✓${NC} Added SOPS_AGE_KEY_FILE to $SHELL_RC"
            echo -e "${YELLOW}⚠${NC} Run 'source $SHELL_RC' or restart your shell to apply"
        else
            echo -e "${GREEN}✓${NC} SOPS_AGE_KEY_FILE already in $SHELL_RC"
        fi
    fi
fi

echo ""
echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "1. Review and update encrypted secrets: sops secrets.yaml"
echo "2. Navigate to environment: cd environments/production/kubernetes"
echo "3. Initialize Terragrunt: terragrunt init"
echo "4. Plan deployment: terragrunt plan"
echo "5. Apply changes: terragrunt apply"
echo ""
echo "📚 For more information, see TERRAGRUNT_README.md"
