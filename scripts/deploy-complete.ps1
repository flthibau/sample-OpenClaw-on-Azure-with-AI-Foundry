<#
.SYNOPSIS
    One-click deployment of OpenClaw on Azure - Fully Automated
    
.DESCRIPTION
    Deploys the complete OpenClaw environment on Azure with zero manual steps:
    - Azure VM with Docker and OpenClaw pre-installed
    - Azure AI Foundry (OpenAI) with GPT-5 model deployed
    - Azure Bastion for secure access
    - Managed Identity with proper role assignments
    - OpenClaw configured and started automatically
    
.PARAMETER ResourceGroupName
    Name of the Azure resource group to create/use
    
.PARAMETER Location
    Azure region for deployment (default: eastus2)
    
.PARAMETER AIModel
    AI model to deploy: gpt-4o, gpt-4o-mini, gpt-5, gpt-5-mini (default: gpt-5)
    
.PARAMETER VMSize
    Azure VM size (default: Standard_D2s_v5)
    
.PARAMETER SkipConfirmation
    Skip the confirmation prompt
    
.EXAMPLE
    ./deploy-complete.ps1 -ResourceGroupName "rg-openclaw-test"
    
.EXAMPLE
    ./deploy-complete.ps1 -ResourceGroupName "rg-openclaw-prod" -Location "westeurope" -AIModel "gpt-5"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $false)]
    [string]$Location = "eastus2",
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("gpt-4o", "gpt-4o-mini", "gpt-35-turbo")]
    [string]$AIModel = "gpt-4o",
    
    [Parameter(Mandatory = $false)]
    [string]$VMSize = "Standard_D2s_v5",
    
    [Parameter(Mandatory = $false)]
    [string]$Environment = "dev",
    
    [Parameter(Mandatory = $false)]
    [string]$AdminUsername = "azureuser",
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipConfirmation
)

$ErrorActionPreference = "Stop"

# Colors for output
function Write-Step { param($Message) Write-Host "`n📌 $Message" -ForegroundColor Cyan }
function Write-Success { param($Message) Write-Host "✅ $Message" -ForegroundColor Green }
function Write-Warning { param($Message) Write-Host "⚠️ $Message" -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host "❌ $Message" -ForegroundColor Red }
function Write-Info { param($Message) Write-Host "ℹ️ $Message" -ForegroundColor Blue }

# Banner
Write-Host @"

╔═══════════════════════════════════════════════════════════════════════════╗
║                                                                           ║
║   🤖 OpenClaw on Azure - Fully Automated Deployment 🤖                    ║
║                                                                           ║
║   This script will deploy:                                                ║
║   ✅ Azure Virtual Machine with Docker & OpenClaw                        ║
║   ✅ Azure AI Foundry with $AIModel model                                ║
║   ✅ Azure Bastion for secure access                                     ║
║   ✅ Managed Identity with role assignments                              ║
║   ✅ Full configuration - OpenClaw starts automatically!                 ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Magenta

# Deployment summary
Write-Host "📋 Deployment Configuration:" -ForegroundColor White
Write-Host "   Resource Group: $ResourceGroupName"
Write-Host "   Location:       $Location"
Write-Host "   AI Model:       $AIModel"
Write-Host "   VM Size:        $VMSize"
Write-Host "   Environment:    $Environment"
Write-Host ""

# Confirmation
if (-not $SkipConfirmation) {
    $confirm = Read-Host "Do you want to proceed with the deployment? (y/N)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-Warning "Deployment cancelled by user."
        exit 0
    }
}

# Check prerequisites
Write-Step "Checking prerequisites..."

# Check Azure CLI
try {
    $azVersion = az version --output json | ConvertFrom-Json
    Write-Success "Azure CLI installed (v$($azVersion.'azure-cli'))"
} catch {
    Write-Error "Azure CLI is not installed. Please install it first."
    Write-Host "   https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
}

# Check login status
Write-Step "Checking Azure login status..."
$account = az account show --output json 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Warning "Not logged in to Azure. Opening login..."
    az login
    $account = az account show --output json | ConvertFrom-Json
}
Write-Success "Logged in as: $($account.user.name)"
Write-Info "Subscription: $($account.name) ($($account.id))"

# Check if location supports Azure OpenAI
Write-Step "Validating Azure region for AI Foundry..."
$supportedRegions = @("eastus", "eastus2", "westus", "westus2", "westus3", "northcentralus", "southcentralus", 
                      "westeurope", "northeurope", "uksouth", "swedencentral", "switzerlandnorth",
                      "australiaeast", "japaneast", "koreacentral", "canadaeast", "francecentral")

if ($Location -notin $supportedRegions) {
    Write-Warning "Region '$Location' may not support Azure OpenAI. Consider: eastus2, westeurope, or swedencentral"
    $proceed = Read-Host "Continue anyway? (y/N)"
    if ($proceed -ne 'y' -and $proceed -ne 'Y') {
        exit 1
    }
}

# Generate secure password
Write-Step "Generating secure VM password..."
$password = -join ((65..90) + (97..122) + (48..57) + (33, 35, 36, 37, 38, 42, 64) | Get-Random -Count 20 | ForEach-Object { [char]$_ })
$securePassword = ConvertTo-SecureString $password -AsPlainText -Force
Write-Success "Secure password generated"

# Create resource group
Write-Step "Creating resource group '$ResourceGroupName'..."
az group create --name $ResourceGroupName --location $Location --output none
Write-Success "Resource group created/verified"

# Deploy infrastructure
Write-Step "Deploying infrastructure (this takes ~10-15 minutes)..."
Write-Info "Deploying: VM, VNet, Bastion, Azure AI Foundry, Model..."

$templateFile = Join-Path $PSScriptRoot "..\infra\main-complete.bicep"

$deploymentOutput = az deployment group create `
    --resource-group $ResourceGroupName `
    --template-file $templateFile `
    --parameters `
        location=$Location `
        baseName="openclaw" `
        environment=$Environment `
        vmAdminUsername=$AdminUsername `
        vmAdminPassword=$password `
        vmSize=$VMSize `
        aiModel=$AIModel `
        enableBastion=$true `
    --output json | ConvertFrom-Json

if (-not $deploymentOutput) {
    Write-Error "Deployment failed. Check the Azure Portal for details."
    exit 1
}

Write-Success "Infrastructure deployed successfully!"

# Extract outputs
$outputs = $deploymentOutput.properties.outputs
$vmName = $outputs.vmName.value
$vmPrivateIp = $outputs.vmPrivateIp.value
$bastionName = $outputs.bastionName.value
$aiFoundryEndpoint = $outputs.aiFoundryEndpoint.value
$aiModelDeployment = $outputs.aiModelDeployment.value

# Wait for cloud-init to complete
Write-Step "Waiting for VM initialization (cloud-init)..."
Write-Info "OpenClaw is being installed and configured on the VM..."

$maxWaitMinutes = 10
$waitedSeconds = 0
$checkInterval = 30

while ($waitedSeconds -lt ($maxWaitMinutes * 60)) {
    Start-Sleep -Seconds $checkInterval
    $waitedSeconds += $checkInterval
    $progress = [math]::Round(($waitedSeconds / ($maxWaitMinutes * 60)) * 100)
    Write-Host "`r   ⏳ Progress: $progress% ($([math]::Floor($waitedSeconds/60))m $($waitedSeconds%60)s / ${maxWaitMinutes}m)" -NoNewline
}

Write-Host ""
Write-Success "VM initialization should be complete"

# Display results
Write-Host @"

╔═══════════════════════════════════════════════════════════════════════════╗
║                                                                           ║
║   🎉 DEPLOYMENT COMPLETE! 🎉                                              ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Green

Write-Host "📋 Deployment Summary:" -ForegroundColor White
Write-Host ""
Write-Host "   🖥️  VM Name:           $vmName"
Write-Host "   🔒 VM Private IP:      $vmPrivateIp"
Write-Host "   🌉 Bastion:            $bastionName"
Write-Host "   🤖 AI Foundry:         $aiFoundryEndpoint"
Write-Host "   🧠 AI Model:           $aiModelDeployment"
Write-Host ""

Write-Host "🔐 VM Credentials:" -ForegroundColor Yellow
Write-Host "   Username: $AdminUsername"
Write-Host "   Password: $password"
Write-Host ""
Write-Host "   ⚠️  SAVE THIS PASSWORD! It won't be shown again." -ForegroundColor Red
Write-Host ""

Write-Host "🚀 How to Connect:" -ForegroundColor Cyan
Write-Host ""
Write-Host "   1. Go to Azure Portal: https://portal.azure.com"
Write-Host "   2. Navigate to: Resource Groups > $ResourceGroupName > $vmName"
Write-Host "   3. Click: Connect > Bastion"
Write-Host "   4. Enter credentials above"
Write-Host "   5. OpenClaw is already running! Use ./status.sh to verify"
Write-Host ""

Write-Host "💡 Quick Commands (once connected):" -ForegroundColor Cyan
Write-Host ""
Write-Host "   ./status.sh    - Check OpenClaw & AI connection status"
Write-Host "   ./start.sh     - Restart OpenClaw if needed"
Write-Host "   docker compose logs -f    - View live logs"
Write-Host ""

# Save credentials to file
$credFile = Join-Path $PSScriptRoot "..\credentials-$ResourceGroupName.txt"
@"
OpenClaw on Azure - Deployment Credentials
==========================================
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

Resource Group: $ResourceGroupName
Location: $Location

VM Name: $vmName
VM Private IP: $vmPrivateIp
Username: $AdminUsername
Password: $password

AI Foundry Endpoint: $aiFoundryEndpoint
AI Model Deployment: $aiModelDeployment

Bastion: $bastionName

Connection URL:
https://portal.azure.com/#@/resource/subscriptions/$($account.id)/resourceGroups/$ResourceGroupName/providers/Microsoft.Compute/virtualMachines/$vmName/bastionHost

⚠️ DELETE THIS FILE AFTER SAVING CREDENTIALS SECURELY!
"@ | Out-File -FilePath $credFile -Encoding UTF8

Write-Success "Credentials saved to: $credFile"
Write-Warning "DELETE this file after saving credentials securely!"

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
Write-Host ""
