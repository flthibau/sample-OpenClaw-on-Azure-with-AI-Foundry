# Deployment Guide

This guide provides detailed instructions for deploying OpenClaw on Azure with AI Foundry.

## Prerequisites

Before you begin, ensure you have:

1. **Azure Subscription** with at least Contributor access
2. **Azure CLI** installed ([Install guide](https://docs.microsoft.com/cli/azure/install-azure-cli))
3. **Azure AI Foundry** workspace with a deployed model (optional, can be configured later)

### Verify Azure CLI Installation

```bash
az version
```

### Login to Azure

```bash
az login
```

## Deployment Options

### Option 1: One-Click Deploy (Azure Portal)

1. Click the "Deploy to Azure" button in the README
2. Fill in the required parameters:
   - **Resource Group**: Create new or select existing
   - **Location**: Choose your preferred region
   - **Admin Username**: VM administrator username
   - **Admin Password**: Strong password (min 12 characters)
3. Click "Review + Create", then "Create"
4. Wait ~8-10 minutes for deployment to complete

### Option 2: PowerShell Script (Windows)

```powershell
# Navigate to the scripts directory
cd sample-OpenClaw-on-Azure-with-AI-Foundry/scripts

# Run the deployment script
./deploy.ps1 -ResourceGroupName "rg-openclaw-sandbox" -Location "eastus2"
```

**Parameters:**
- `-ResourceGroupName` (Required): Name for the Azure resource group
- `-Location`: Azure region (default: eastus2)
- `-Environment`: dev, test, or prod (default: dev)
- `-AdminUsername`: VM admin username (default: azureuser)
- `-EnableBastion`: Deploy Azure Bastion (default: $true)
- `-SkipConfirmation`: Skip confirmation prompt

### Option 3: Bash Script (Linux/macOS)

```bash
# Navigate to the scripts directory
cd sample-OpenClaw-on-Azure-with-AI-Foundry/scripts

# Make the script executable
chmod +x deploy.sh

# Run the deployment script
./deploy.sh --resource-group "rg-openclaw-sandbox" --location "eastus2"
```

**Options:**
- `-g, --resource-group` (Required): Resource group name
- `-l, --location`: Azure region (default: eastus2)
- `-e, --environment`: dev, test, or prod (default: dev)
- `-u, --admin-username`: VM admin username (default: azureuser)
- `--no-bastion`: Skip Azure Bastion deployment
- `-y, --yes`: Skip confirmation prompt

### Option 4: Azure CLI Direct Deployment

```bash
# Create resource group
az group create --name rg-openclaw-sandbox --location eastus2

# Deploy infrastructure
az deployment group create \
  --resource-group rg-openclaw-sandbox \
  --template-file infra/main.bicep \
  --parameters \
    adminUsername=azureuser \
    adminPassword='YourStrongPassword123!' \
    environment=dev
```

## Post-Deployment Configuration

### 1. Connect to the VM

After deployment completes:

1. Go to [Azure Portal](https://portal.azure.com)
2. Navigate to your resource group
3. Click on the Virtual Machine
4. Click **Connect** → **Bastion**
5. Enter your username and password
6. Click **Connect**

### 2. Configure Azure AI Foundry Access

The VM uses a Managed Identity for secure, keyless access to Azure AI Foundry.

**Grant Access to Managed Identity:**

```bash
# Get the Managed Identity Principal ID from deployment outputs
# Or find it in Azure Portal > VM > Identity > System assigned > Object ID

# Grant Cognitive Services OpenAI User role
az role assignment create \
  --assignee <MANAGED_IDENTITY_PRINCIPAL_ID> \
  --role "Cognitive Services OpenAI User" \
  --scope /subscriptions/<SUBSCRIPTION_ID>/resourceGroups/<AI_FOUNDRY_RG>/providers/Microsoft.CognitiveServices/accounts/<AI_FOUNDRY_NAME>
```

### 3. Verify AI Foundry Connection

Once connected to the VM:

```bash
cd ~/openclaw
./setup-azure-ai.sh
```

This will test the Managed Identity authentication.

### 4. Configure OpenClaw

```bash
cd ~/openclaw

# Copy the example environment file
cp .env.example .env

# Edit the configuration
nano .env
```

Add your Azure AI Foundry settings:

```env
# Azure AI Foundry Configuration
AZURE_USE_MANAGED_IDENTITY=true
AZURE_OPENAI_ENDPOINT=https://your-resource.openai.azure.com/
AZURE_OPENAI_DEPLOYMENT=gpt-5
```

### 5. Start OpenClaw

```bash
./start.sh
```

Or manually with Docker Compose:

```bash
docker compose up -d

# View logs
docker compose logs -f
```

## Deployment Architecture

The deployment creates the following resources:

| Resource | Purpose | SKU |
|----------|---------|-----|
| Virtual Network | Isolated network for the VM | - |
| Network Security Group | Firewall rules (default deny) | - |
| Virtual Machine | Runs OpenClaw | Standard_D2s_v5 |
| Managed Identity | Keyless auth to Azure AI | User Assigned |
| Azure Bastion | Secure VM access | Standard |
| Public IP | Bastion connectivity | Standard |

## Customization

### VM Size

Change the VM size by modifying the `vmSize` parameter:

```bicep
param vmSize string = 'Standard_D4s_v5'  // Upgrade for more power
```

Available sizes:
- `Standard_D2s_v5`: 2 vCPU, 8 GB RAM (default)
- `Standard_D4s_v5`: 4 vCPU, 16 GB RAM
- `Standard_D8s_v5`: 8 vCPU, 32 GB RAM

### Auto-Shutdown

The VM is configured to auto-shutdown at 7 PM UTC by default. Modify in `main.bicep`:

```bicep
param autoShutdownTime string = '23:00'  // 11 PM UTC
param enableAutoShutdown bool = true
```

### Disable Bastion

To reduce costs, you can deploy without Bastion:

```bash
./deploy.ps1 -ResourceGroupName "rg-openclaw" -EnableBastion $false
```

You'll need an alternative access method (VPN, ExpressRoute, etc.).

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues and solutions.

## Cleanup

To delete all resources:

```bash
az group delete --name rg-openclaw-sandbox --yes --no-wait
```

⚠️ This will permanently delete all resources in the resource group.
