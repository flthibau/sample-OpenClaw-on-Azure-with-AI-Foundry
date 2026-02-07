#!/bin/bash
#
# OpenClaw on Azure - Fully Automated Deployment
# 
# Deploys the complete OpenClaw environment with zero manual steps:
# - Azure VM with Docker and OpenClaw pre-installed
# - Azure AI Foundry (OpenAI) with GPT-5 model deployed
# - Azure Bastion for secure access
# - Managed Identity with proper role assignments
# - OpenClaw configured and started automatically
#
# Usage:
#   ./deploy-complete.sh --resource-group "rg-openclaw-test"
#   ./deploy-complete.sh -g "rg-openclaw-prod" -l "westeurope" -m "gpt-5"
#

set -e

# Default values
RESOURCE_GROUP=""
LOCATION="eastus2"
AI_MODEL="gpt-5"
VM_SIZE="Standard_D2s_v5"
ENVIRONMENT="dev"
ADMIN_USERNAME="azureuser"
SKIP_CONFIRMATION=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Helper functions
print_step() { echo -e "\n${CYAN}📌 $1${NC}"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️ $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ️ $1${NC}"; }

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
        -m|--model)
            AI_MODEL="$2"
            shift 2
            ;;
        -s|--vm-size)
            VM_SIZE="$2"
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
        -y|--yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 -g <resource-group> [options]"
            echo ""
            echo "Options:"
            echo "  -g, --resource-group  Resource group name (required)"
            echo "  -l, --location        Azure region (default: eastus2)"
            echo "  -m, --model           AI model: gpt-4o, gpt-5, etc. (default: gpt-5)"
            echo "  -s, --vm-size         VM size (default: Standard_D2s_v5)"
            echo "  -e, --environment     Environment: dev, test, prod (default: dev)"
            echo "  -u, --admin-username  VM admin username (default: azureuser)"
            echo "  -y, --yes             Skip confirmation prompt"
            echo "  -h, --help            Show this help message"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate required arguments
if [ -z "$RESOURCE_GROUP" ]; then
    print_error "Resource group name is required. Use -g or --resource-group"
    exit 1
fi

# Banner
echo -e "${MAGENTA}"
cat << 'EOF'

╔═══════════════════════════════════════════════════════════════════════════╗
║                                                                           ║
║   🤖 OpenClaw on Azure - Fully Automated Deployment 🤖                    ║
║                                                                           ║
║   This script will deploy:                                                ║
║   ✅ Azure Virtual Machine with Docker & OpenClaw                        ║
║   ✅ Azure AI Foundry with AI model                                      ║
║   ✅ Azure Bastion for secure access                                     ║
║   ✅ Managed Identity with role assignments                              ║
║   ✅ Full configuration - OpenClaw starts automatically!                 ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝

EOF
echo -e "${NC}"

# Deployment summary
echo "📋 Deployment Configuration:"
echo "   Resource Group: $RESOURCE_GROUP"
echo "   Location:       $LOCATION"
echo "   AI Model:       $AI_MODEL"
echo "   VM Size:        $VM_SIZE"
echo "   Environment:    $ENVIRONMENT"
echo ""

# Confirmation
if [ "$SKIP_CONFIRMATION" = false ]; then
    read -p "Do you want to proceed with the deployment? (y/N) " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_warning "Deployment cancelled by user."
        exit 0
    fi
fi

# Check prerequisites
print_step "Checking prerequisites..."

# Check Azure CLI
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed. Please install it first."
    echo "   https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
fi
print_success "Azure CLI installed"

# Check login status
print_step "Checking Azure login status..."
if ! az account show &> /dev/null; then
    print_warning "Not logged in to Azure. Opening login..."
    az login
fi
ACCOUNT_NAME=$(az account show --query name -o tsv)
ACCOUNT_ID=$(az account show --query id -o tsv)
USER_NAME=$(az account show --query user.name -o tsv)
print_success "Logged in as: $USER_NAME"
print_info "Subscription: $ACCOUNT_NAME ($ACCOUNT_ID)"

# Generate secure password
print_step "Generating secure VM password..."
PASSWORD=$(openssl rand -base64 16 | tr -d '/+=' | head -c 20)
PASSWORD="${PASSWORD}Aa1!"  # Ensure complexity requirements
print_success "Secure password generated"

# Create resource group
print_step "Creating resource group '$RESOURCE_GROUP'..."
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none
print_success "Resource group created/verified"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/../infra/main-complete.bicep"

# Deploy infrastructure
print_step "Deploying infrastructure (this takes ~10-15 minutes)..."
print_info "Deploying: VM, VNet, Bastion, Azure AI Foundry, Model..."

DEPLOYMENT_OUTPUT=$(az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$TEMPLATE_FILE" \
    --parameters \
        location="$LOCATION" \
        baseName="openclaw" \
        environment="$ENVIRONMENT" \
        vmAdminUsername="$ADMIN_USERNAME" \
        vmAdminPassword="$PASSWORD" \
        vmSize="$VM_SIZE" \
        aiModel="$AI_MODEL" \
        enableBastion=true \
    --output json)

if [ $? -ne 0 ]; then
    print_error "Deployment failed. Check the Azure Portal for details."
    exit 1
fi

print_success "Infrastructure deployed successfully!"

# Extract outputs
VM_NAME=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.vmName.value')
VM_PRIVATE_IP=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.vmPrivateIp.value')
BASTION_NAME=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.bastionName.value')
AI_FOUNDRY_ENDPOINT=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.aiFoundryEndpoint.value')
AI_MODEL_DEPLOYMENT=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.aiModelDeployment.value')

# Wait for cloud-init
print_step "Waiting for VM initialization (cloud-init)..."
print_info "OpenClaw is being installed and configured on the VM..."

MAX_WAIT=600  # 10 minutes
WAITED=0
INTERVAL=30

while [ $WAITED -lt $MAX_WAIT ]; do
    sleep $INTERVAL
    WAITED=$((WAITED + INTERVAL))
    PROGRESS=$((WAITED * 100 / MAX_WAIT))
    MINUTES=$((WAITED / 60))
    SECONDS=$((WAITED % 60))
    echo -ne "\r   ⏳ Progress: ${PROGRESS}% (${MINUTES}m ${SECONDS}s / $((MAX_WAIT/60))m)"
done

echo ""
print_success "VM initialization should be complete"

# Display results
echo -e "${GREEN}"
cat << 'EOF'

╔═══════════════════════════════════════════════════════════════════════════╗
║                                                                           ║
║   🎉 DEPLOYMENT COMPLETE! 🎉                                              ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝

EOF
echo -e "${NC}"

echo "📋 Deployment Summary:"
echo ""
echo "   🖥️  VM Name:           $VM_NAME"
echo "   🔒 VM Private IP:      $VM_PRIVATE_IP"
echo "   🌉 Bastion:            $BASTION_NAME"
echo "   🤖 AI Foundry:         $AI_FOUNDRY_ENDPOINT"
echo "   🧠 AI Model:           $AI_MODEL_DEPLOYMENT"
echo ""

echo -e "${YELLOW}🔐 VM Credentials:${NC}"
echo "   Username: $ADMIN_USERNAME"
echo "   Password: $PASSWORD"
echo ""
echo -e "${RED}   ⚠️  SAVE THIS PASSWORD! It won't be shown again.${NC}"
echo ""

echo -e "${CYAN}🚀 How to Connect:${NC}"
echo ""
echo "   1. Go to Azure Portal: https://portal.azure.com"
echo "   2. Navigate to: Resource Groups > $RESOURCE_GROUP > $VM_NAME"
echo "   3. Click: Connect > Bastion"
echo "   4. Enter credentials above"
echo "   5. OpenClaw is already running! Use ./status.sh to verify"
echo ""

echo -e "${CYAN}💡 Quick Commands (once connected):${NC}"
echo ""
echo "   ./status.sh    - Check OpenClaw & AI connection status"
echo "   ./start.sh     - Restart OpenClaw if needed"
echo "   docker compose logs -f    - View live logs"
echo ""

# Save credentials to file
CRED_FILE="$SCRIPT_DIR/../credentials-$RESOURCE_GROUP.txt"
cat > "$CRED_FILE" << EOF
OpenClaw on Azure - Deployment Credentials
==========================================
Generated: $(date '+%Y-%m-%d %H:%M:%S')

Resource Group: $RESOURCE_GROUP
Location: $LOCATION

VM Name: $VM_NAME
VM Private IP: $VM_PRIVATE_IP
Username: $ADMIN_USERNAME
Password: $PASSWORD

AI Foundry Endpoint: $AI_FOUNDRY_ENDPOINT
AI Model Deployment: $AI_MODEL_DEPLOYMENT

Bastion: $BASTION_NAME

Connection URL:
https://portal.azure.com/#@/resource/subscriptions/$ACCOUNT_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Compute/virtualMachines/$VM_NAME/bastionHost

⚠️ DELETE THIS FILE AFTER SAVING CREDENTIALS SECURELY!
EOF

print_success "Credentials saved to: $CRED_FILE"
print_warning "DELETE this file after saving credentials securely!"

echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""
