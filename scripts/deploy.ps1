<#
.SYNOPSIS
    Deploys OpenClaw on Azure with AI Foundry infrastructure.

.DESCRIPTION
    This script deploys the complete infrastructure for running OpenClaw
    on Azure using Bicep templates. It creates a secure sandbox environment
    with Azure Bastion for access.

.PARAMETER ResourceGroupName
    The name of the resource group to create or use.

.PARAMETER Location
    The Azure region for deployment. Defaults to 'eastus2'.

.PARAMETER Environment
    The environment name (dev, test, prod). Defaults to 'dev'.

.PARAMETER AdminUsername
    The administrator username for the VM. Defaults to 'azureuser'.

.PARAMETER EnableBastion
    Whether to deploy Azure Bastion. Defaults to $true.

.PARAMETER SkipConfirmation
    Skip the confirmation prompt before deployment.

.EXAMPLE
    ./deploy.ps1 -ResourceGroupName "rg-openclaw-sandbox" -Location "eastus2"

.EXAMPLE
    ./deploy.ps1 -ResourceGroupName "rg-openclaw-prod" -Environment "prod" -SkipConfirmation
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string]$Location = "eastus2",

    [Parameter(Mandatory = $false)]
    [ValidateSet("dev", "test", "prod")]
    [string]$Environment = "dev",

    [Parameter(Mandatory = $false)]
    [string]$AdminUsername = "azureuser",

    [Parameter(Mandatory = $false)]
    [bool]$EnableBastion = $true,

    [Parameter(Mandatory = $false)]
    [switch]$SkipConfirmation
)

$ErrorActionPreference = "Stop"

# Banner
Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   🐾 OpenClaw on Azure with AI Foundry - Deployment Script   ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Check for Azure CLI
Write-Host "🔍 Checking prerequisites..." -ForegroundColor Yellow
$azVersion = az version 2>$null | ConvertFrom-Json
if (-not $azVersion) {
    Write-Host "❌ Azure CLI is not installed. Please install it from https://aka.ms/installazurecli" -ForegroundColor Red
    exit 1
}
Write-Host "✅ Azure CLI version: $($azVersion.'azure-cli')" -ForegroundColor Green

# Check login status
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "🔐 Please login to Azure..." -ForegroundColor Yellow
    az login
    $account = az account show | ConvertFrom-Json
}
Write-Host "✅ Logged in as: $($account.user.name)" -ForegroundColor Green
Write-Host "   Subscription: $($account.name) ($($account.id))" -ForegroundColor Gray

# Deployment summary
Write-Host ""
Write-Host "📋 Deployment Configuration:" -ForegroundColor Cyan
Write-Host "   Resource Group: $ResourceGroupName"
Write-Host "   Location: $Location"
Write-Host "   Environment: $Environment"
Write-Host "   Admin Username: $AdminUsername"
Write-Host "   Azure Bastion: $EnableBastion"
Write-Host ""

# Estimated costs
Write-Host "💰 Estimated Monthly Cost:" -ForegroundColor Yellow
Write-Host "   VM (Standard_D2s_v5): ~$35/month"
if ($EnableBastion) {
    Write-Host "   Azure Bastion (Standard): ~$140/month (or ~$0.19/hour when used)"
}
Write-Host "   Storage (Premium SSD): ~$10/month"
Write-Host "   Total: ~$(if ($EnableBastion) { '$185' } else { '$45' })/month (excluding AI Foundry usage)"
Write-Host ""

# Confirmation
if (-not $SkipConfirmation) {
    $confirm = Read-Host "Do you want to continue? (y/N)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-Host "Deployment cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# Get admin password securely
Write-Host ""
$securePassword = Read-Host "Enter admin password for VM (min 12 chars, complex)" -AsSecureString
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
$adminPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

if ($adminPassword.Length -lt 12) {
    Write-Host "❌ Password must be at least 12 characters long" -ForegroundColor Red
    exit 1
}

# Create resource group
Write-Host ""
Write-Host "📦 Creating resource group '$ResourceGroupName' in '$Location'..." -ForegroundColor Yellow
az group create --name $ResourceGroupName --location $Location --output none
Write-Host "✅ Resource group ready" -ForegroundColor Green

# Get the script directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$infraDir = Join-Path (Split-Path -Parent $scriptDir) "infra"
$bicepFile = Join-Path $infraDir "main.bicep"

if (-not (Test-Path $bicepFile)) {
    Write-Host "❌ Bicep template not found at: $bicepFile" -ForegroundColor Red
    exit 1
}

# Deploy infrastructure
Write-Host ""
Write-Host "🚀 Deploying infrastructure (this takes about 8-10 minutes)..." -ForegroundColor Yellow
Write-Host ""

$deploymentName = "openclaw-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

$deploymentResult = az deployment group create `
    --resource-group $ResourceGroupName `
    --name $deploymentName `
    --template-file $bicepFile `
    --parameters `
        location=$Location `
        environment=$Environment `
        adminUsername=$AdminUsername `
        adminPassword=$adminPassword `
        enableBastion=$EnableBastion `
    --output json | ConvertFrom-Json

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Deployment failed!" -ForegroundColor Red
    exit 1
}

# Clear password from memory
$adminPassword = $null
[System.GC]::Collect()

# Get outputs
Write-Host ""
Write-Host "✅ Deployment completed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "📋 Deployment Outputs:" -ForegroundColor Cyan

$outputs = $deploymentResult.properties.outputs
Write-Host "   VM Name: $($outputs.vmName.value)"
Write-Host "   VM Private IP: $($outputs.vmPrivateIp.value)"
Write-Host "   Managed Identity Client ID: $($outputs.managedIdentityClientId.value)"

if ($EnableBastion) {
    Write-Host "   Bastion Name: $($outputs.bastionName.value)"
}

Write-Host ""
Write-Host "🔗 Next Steps:" -ForegroundColor Cyan
Write-Host ""
Write-Host "   1. Connect to your VM via Azure Bastion:"
Write-Host "      - Go to Azure Portal > Resource Groups > $ResourceGroupName"
Write-Host "      - Click on VM '$($outputs.vmName.value)'"
Write-Host "      - Click 'Connect' > 'Bastion'"
Write-Host "      - Enter username '$AdminUsername' and your password"
Write-Host ""
Write-Host "   2. Configure Azure AI Foundry access:"
Write-Host "      - Grant 'Cognitive Services OpenAI User' role to the Managed Identity"
Write-Host "      - Principal ID: $($outputs.managedIdentityPrincipalId.value)"
Write-Host ""
Write-Host "   3. Start OpenClaw:"
Write-Host "      cd ~/openclaw"
Write-Host "      ./setup-azure-ai.sh"
Write-Host "      ./start.sh"
Write-Host ""
Write-Host "📚 Documentation: https://github.com/YOUR_USERNAME/sample-OpenClaw-on-Azure-with-AI-Foundry"
Write-Host ""
