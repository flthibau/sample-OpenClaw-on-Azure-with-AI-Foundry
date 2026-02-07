#!/bin/bash
# =============================================================
# OpenClaw on Azure with AI Foundry - Deployment Script
# =============================================================
#
# Usage:
#   ./deploy.sh --resource-group "rg-openclaw-sandbox" --location "eastus2"
#
# Options:
#   -g, --resource-group    Resource group name (required)
#   -l, --location          Azure region (default: eastus2)
#   -e, --environment       Environment name: dev, test, prod (default: dev)
#   -u, --admin-username    VM admin username (default: azureuser)
#   --no-bastion           Skip Azure Bastion deployment
#   -y, --yes              Skip confirmation prompt
#   -h, --help             Show this help message
#

set -e

# Default values
LOCATION="eastus2"
ENVIRONMENT="dev"
ADMIN_USERNAME="azureuser"
ENABLE_BASTION="true"
SKIP_CONFIRM=false
RESOURCE_GROUP=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Print banner
print_banner() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║   🐾 OpenClaw on Azure with AI Foundry - Deployment Script   ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Print help
print_help() {
    echo "Usage: $0 --resource-group <name> [options]"
    echo ""
    echo "Required:"
    echo "  -g, --resource-group    Resource group name"
    echo ""
    echo "Options:"
    echo "  -l, --location          Azure region (default: eastus2)"
    echo "  -e, --environment       Environment: dev, test, prod (default: dev)"
    echo "  -u, --admin-username    VM admin username (default: azureuser)"
    echo "  --no-bastion           Skip Azure Bastion deployment"
    echo "  -y, --yes              Skip confirmation prompt"
    echo "  -h, --help             Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 --resource-group rg-openclaw-sandbox --location eastus2"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -l|--location)
            LOCATION="$2"
            shift 2
            ;;
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -u|--admin-username)
            ADMIN_USERNAME="$2"
            shift 2
            ;;
        --no-bastion)
            ENABLE_BASTION="false"
            shift
            ;;
        -y|--yes)
            SKIP_CONFIRM=true
            shift
            ;;
        -h|--help)
            print_help
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            print_help
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$RESOURCE_GROUP" ]; then
    echo -e "${RED}❌ Error: Resource group name is required${NC}"
    echo ""
    print_help
    exit 1
fi

# Print banner
print_banner

# Check for Azure CLI
echo -e "${YELLOW}🔍 Checking prerequisites...${NC}"
if ! command -v az &> /dev/null; then
    echo -e "${RED}❌ Azure CLI is not installed. Please install it from https://aka.ms/installazurecli${NC}"
    exit 1
fi

AZ_VERSION=$(az version --query '"azure-cli"' -o tsv 2>/dev/null)
echo -e "${GREEN}✅ Azure CLI version: $AZ_VERSION${NC}"

# Check login status
ACCOUNT=$(az account show 2>/dev/null) || {
    echo -e "${YELLOW}🔐 Please login to Azure...${NC}"
    az login
    ACCOUNT=$(az account show)
}

USER_NAME=$(echo $ACCOUNT | jq -r '.user.name')
SUB_NAME=$(echo $ACCOUNT | jq -r '.name')
SUB_ID=$(echo $ACCOUNT | jq -r '.id')

echo -e "${GREEN}✅ Logged in as: $USER_NAME${NC}"
echo -e "   Subscription: $SUB_NAME ($SUB_ID)"

# Deployment summary
echo ""
echo -e "${CYAN}📋 Deployment Configuration:${NC}"
echo "   Resource Group: $RESOURCE_GROUP"
echo "   Location: $LOCATION"
echo "   Environment: $ENVIRONMENT"
echo "   Admin Username: $ADMIN_USERNAME"
echo "   Azure Bastion: $ENABLE_BASTION"
echo ""

# Estimated costs
echo -e "${YELLOW}💰 Estimated Monthly Cost:${NC}"
echo "   VM (Standard_D2s_v5): ~\$35/month"
if [ "$ENABLE_BASTION" = "true" ]; then
    echo "   Azure Bastion (Standard): ~\$140/month (or ~\$0.19/hour when used)"
fi
echo "   Storage (Premium SSD): ~\$10/month"
if [ "$ENABLE_BASTION" = "true" ]; then
    echo "   Total: ~\$185/month (excluding AI Foundry usage)"
else
    echo "   Total: ~\$45/month (excluding AI Foundry usage)"
fi
echo ""

# Confirmation
if [ "$SKIP_CONFIRM" = false ]; then
    read -p "Do you want to continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Deployment cancelled."
        exit 0
    fi
fi

# Get admin password
echo ""
read -s -p "Enter admin password for VM (min 12 chars, complex): " ADMIN_PASSWORD
echo ""

if [ ${#ADMIN_PASSWORD} -lt 12 ]; then
    echo -e "${RED}❌ Password must be at least 12 characters long${NC}"
    exit 1
fi

# Create resource group
echo ""
echo -e "${YELLOW}📦 Creating resource group '$RESOURCE_GROUP' in '$LOCATION'...${NC}"
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none
echo -e "${GREEN}✅ Resource group ready${NC}"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")/infra"
BICEP_FILE="$INFRA_DIR/main.bicep"

if [ ! -f "$BICEP_FILE" ]; then
    echo -e "${RED}❌ Bicep template not found at: $BICEP_FILE${NC}"
    exit 1
fi

# Deploy infrastructure
echo ""
echo -e "${YELLOW}🚀 Deploying infrastructure (this takes about 8-10 minutes)...${NC}"
echo ""

DEPLOYMENT_NAME="openclaw-$(date +%Y%m%d-%H%M%S)"

DEPLOYMENT_OUTPUT=$(az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$DEPLOYMENT_NAME" \
    --template-file "$BICEP_FILE" \
    --parameters \
        location="$LOCATION" \
        environment="$ENVIRONMENT" \
        adminUsername="$ADMIN_USERNAME" \
        adminPassword="$ADMIN_PASSWORD" \
        enableBastion="$ENABLE_BASTION" \
    --output json)

# Clear password from memory
ADMIN_PASSWORD=""

# Check deployment status
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Deployment failed!${NC}"
    exit 1
fi

# Get outputs
echo ""
echo -e "${GREEN}✅ Deployment completed successfully!${NC}"
echo ""
echo -e "${CYAN}📋 Deployment Outputs:${NC}"

VM_NAME=$(echo $DEPLOYMENT_OUTPUT | jq -r '.properties.outputs.vmName.value')
VM_IP=$(echo $DEPLOYMENT_OUTPUT | jq -r '.properties.outputs.vmPrivateIp.value')
MI_CLIENT_ID=$(echo $DEPLOYMENT_OUTPUT | jq -r '.properties.outputs.managedIdentityClientId.value')
MI_PRINCIPAL_ID=$(echo $DEPLOYMENT_OUTPUT | jq -r '.properties.outputs.managedIdentityPrincipalId.value')

echo "   VM Name: $VM_NAME"
echo "   VM Private IP: $VM_IP"
echo "   Managed Identity Client ID: $MI_CLIENT_ID"

if [ "$ENABLE_BASTION" = "true" ]; then
    BASTION_NAME=$(echo $DEPLOYMENT_OUTPUT | jq -r '.properties.outputs.bastionName.value')
    echo "   Bastion Name: $BASTION_NAME"
fi

echo ""
echo -e "${CYAN}🔗 Next Steps:${NC}"
echo ""
echo "   1. Connect to your VM via Azure Bastion:"
echo "      - Go to Azure Portal > Resource Groups > $RESOURCE_GROUP"
echo "      - Click on VM '$VM_NAME'"
echo "      - Click 'Connect' > 'Bastion'"
echo "      - Enter username '$ADMIN_USERNAME' and your password"
echo ""
echo "   2. Configure Azure AI Foundry access:"
echo "      - Grant 'Cognitive Services OpenAI User' role to the Managed Identity"
echo "      - Principal ID: $MI_PRINCIPAL_ID"
echo ""
echo "   3. Start OpenClaw:"
echo "      cd ~/openclaw"
echo "      ./setup-azure-ai.sh"
echo "      ./start.sh"
echo ""
echo "📚 Documentation: https://github.com/YOUR_USERNAME/sample-OpenClaw-on-Azure-with-AI-Foundry"
echo ""
