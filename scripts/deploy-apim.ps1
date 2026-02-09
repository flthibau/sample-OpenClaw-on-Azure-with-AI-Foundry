#!/usr/bin/env pwsh
#
# OpenClaw on Azure - Complete Deployment with APIM
# Native installation + Azure AI Foundry + APIM
#

param(
    [string]$ResourceGroup = "rg-openclaw",
    [string]$Location = "swedencentral",
    [string]$VmName = "vm-openclaw",
    [string]$AdminUsername = "azureuser",
    [string]$ModelName = "gpt-5.2-codex",
    [string]$ModelVersion = "2026-01-01",
    [string]$PublisherEmail = "admin@contoso.com",
    [string]$BingSearchApiKey = ""
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     🦞 OpenClaw on Azure - Deployment with APIM 🦞             ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# Prerequisites check
# =============================================================================

Write-Host "🔍 Checking prerequisites..." -ForegroundColor Yellow

# Check Azure CLI
try {
    $azCmd = Get-Command az -ErrorAction Stop
    Write-Host "   ✅ Azure CLI found: $($azCmd.Source)" -ForegroundColor Green
} catch {
    Write-Host "❌ Azure CLI not installed. Install it from https://aka.ms/installazurecliwindows" -ForegroundColor Red
    exit 1
}

# Check Azure connection
$account = az account show --query name -o tsv 2>$null
if (-not $account) {
    Write-Host "⚠️ Not connected to Azure. Connecting..." -ForegroundColor Yellow
    az login
    $account = az account show --query name -o tsv
}
Write-Host "   ✅ Connected to: $account" -ForegroundColor Green

# =============================================================================
# Generate passwords
# =============================================================================

$VmPassword = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 16 | ForEach-Object {[char]$_}) + "!Aa1"
$GatewayPassword = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 12 | ForEach-Object {[char]$_}) + "!"

# =============================================================================
# Step 1: Create the Resource Group
# =============================================================================

Write-Host ""
Write-Host "📦 Step 1/6: Creating the Resource Group..." -ForegroundColor Yellow
az group create -n $ResourceGroup -l $Location -o none
Write-Host "   ✅ Resource Group '$ResourceGroup' created" -ForegroundColor Green

# =============================================================================
# Step 2: Deploy the Bicep infrastructure
# =============================================================================

Write-Host ""
Write-Host "🏗️ Step 2/6: Deploying infrastructure (VM + AI + APIM + Bastion)..." -ForegroundColor Yellow
Write-Host "   ⏳ This step may take 15-20 minutes..." -ForegroundColor Gray

$bicepPath = Join-Path $PSScriptRoot "..\infra\main-apim.bicep"

# Check that the Bicep file exists
if (-not (Test-Path $bicepPath)) {
    Write-Host "❌ Bicep file not found: $bicepPath" -ForegroundColor Red
    exit 1
}

$deploymentResult = az deployment group create `
    -g $ResourceGroup `
    --template-file $bicepPath `
    --parameters baseName="openclaw" `
                 adminUsername=$AdminUsername `
                 adminPassword=$VmPassword `
                 modelName=$ModelName `
                 modelVersion=$ModelVersion `
                 publisherEmail=$PublisherEmail `
                 bingSearchApiKey=$BingSearchApiKey `
    --query "properties.outputs" -o json | ConvertFrom-Json

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Bicep deployment failed" -ForegroundColor Red
    exit 1
}

$VmNameOutput = $deploymentResult.vmName.value
$ApimGatewayUrl = $deploymentResult.apimGatewayUrl.value
$ApimName = $deploymentResult.apimName.value
$AiFoundryEndpoint = $deploymentResult.aiFoundryEndpoint.value
$BastionName = $deploymentResult.bastionName.value

Write-Host "   ✅ Infrastructure deployed" -ForegroundColor Green

# =============================================================================
# Step 3: Retrieve the APIM key
# =============================================================================

Write-Host ""
Write-Host "🔑 Step 3/6: Retrieving the APIM key..." -ForegroundColor Yellow

$ApimKey = az rest --method post `
    --uri "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName/subscriptions/openclaw-subscription/listSecrets?api-version=2024-05-01" `
    --query "primaryKey" -o tsv

if (-not $ApimKey) {
    Write-Host "⚠️ Unable to retrieve the APIM key. Manual retrieval required." -ForegroundColor Yellow
    $ApimKey = "RETRIEVE_MANUALLY"
}

Write-Host "   ✅ APIM key retrieved" -ForegroundColor Green

# =============================================================================
# Step 4: Configure OpenClaw on the VM (via Bastion/Serial Console)
# =============================================================================

Write-Host ""
Write-Host "⚙️ Step 4/6: Waiting for VM configuration (5 minutes)..." -ForegroundColor Yellow
Write-Host "   ⏳ Cloud-init is installing Node.js and OpenClaw..." -ForegroundColor Gray
Start-Sleep -Seconds 300

# =============================================================================
# Step 5: Create the OpenClaw configuration file
# =============================================================================

Write-Host ""
Write-Host "📝 Step 5/6: Preparing OpenClaw configuration..." -ForegroundColor Yellow

$OpenClawConfig = @"
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "azure-openai/$ModelName",
        "fallbacks": ["azure-openai/gpt-5.2", "azure-openai/gpt-4o"]
      },
      "models": {
        "azure-openai/$ModelName": { "alias": "Codex 5.2" },
        "azure-openai/gpt-5.2": { "alias": "GPT-5.2" },
        "azure-openai/gpt-4o": { "alias": "GPT-4o" }
      }
    }
  },
  "models": {
    "mode": "merge",
    "providers": {
      "azure-openai": {
        "baseUrl": "$ApimGatewayUrl/openai",
        "apiKey": "$ApimKey",
        "api": "openai-completions",
        "models": [
          { "id": "$ModelName", "name": "GPT-5.2 Codex", "reasoning": true },
          { "id": "gpt-5.2", "name": "GPT-5.2", "reasoning": true },
          { "id": "gpt-4o", "name": "GPT-4o" }
        ]
      }
    }
  },
  "gateway": {
    "bind": "loopback",
    "port": 18789,
    "auth": {
      "mode": "password",
      "password": "$GatewayPassword"
    }
  }
}
"@

# Save the config locally
$ConfigPath = Join-Path $PSScriptRoot "openclaw-config-$ResourceGroup.json"
$OpenClawConfig | Out-File -FilePath $ConfigPath -Encoding utf8

Write-Host "   ✅ OpenClaw configuration saved: $ConfigPath" -ForegroundColor Green

# =============================================================================
# Step 6: Final summary
# =============================================================================

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║              🎉 DEPLOYMENT COMPLETE! 🎉                        ║" -ForegroundColor Green
Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

Write-Host "🖥️ VM ACCESS (via Bastion):" -ForegroundColor Cyan
Write-Host "   1. Go to https://portal.azure.com" -ForegroundColor White
Write-Host "   2. Resource Groups → $ResourceGroup → $VmNameOutput" -ForegroundColor White
Write-Host "   3. Click 'Connect' → 'Bastion'" -ForegroundColor White
Write-Host "   4. Username: $AdminUsername" -ForegroundColor White
Write-Host "   5. Password: $VmPassword" -ForegroundColor White
Write-Host ""

Write-Host "⚙️ OPENCLAW CONFIGURATION (run on the VM):" -ForegroundColor Cyan
Write-Host "   1. Copy the config file into the VM:" -ForegroundColor White
Write-Host "      cat > ~/.openclaw/openclaw.json << 'EOF'" -ForegroundColor Gray
Write-Host "      $OpenClawConfig" -ForegroundColor Gray
Write-Host "      EOF" -ForegroundColor Gray
Write-Host ""
Write-Host "   2. Run the onboarding:" -ForegroundColor White
Write-Host "      openclaw onboard --install-daemon" -ForegroundColor Gray
Write-Host ""
Write-Host "   3. Or start manually:" -ForegroundColor White
Write-Host "      ./start.sh" -ForegroundColor Gray
Write-Host ""

Write-Host "🔑 CREDENTIALS:" -ForegroundColor Cyan
Write-Host "   Gateway Password: $GatewayPassword" -ForegroundColor White
Write-Host "   APIM Key: $ApimKey" -ForegroundColor White
Write-Host "   APIM Endpoint: $ApimGatewayUrl/openai" -ForegroundColor White
Write-Host ""

Write-Host "🤖 CONFIGURED MODELS:" -ForegroundColor Cyan
Write-Host "   - $ModelName (primary)" -ForegroundColor White
Write-Host "   - gpt-5.2 (fallback)" -ForegroundColor White
Write-Host "   - gpt-4o (fallback)" -ForegroundColor White
Write-Host ""

Write-Host "💰 TO SAVE COSTS:" -ForegroundColor Yellow
Write-Host "   Stop the VM:" -ForegroundColor White
Write-Host "   az vm deallocate -g $ResourceGroup -n $VmNameOutput" -ForegroundColor Gray
Write-Host ""
Write-Host "   Restart the VM:" -ForegroundColor White
Write-Host "   az vm start -g $ResourceGroup -n $VmNameOutput" -ForegroundColor Gray
Write-Host ""

Write-Host "🗑️ TO DELETE:" -ForegroundColor Yellow
Write-Host "   az group delete -n $ResourceGroup --yes --no-wait" -ForegroundColor Gray
Write-Host ""

# =============================================================================
# Save credentials
# =============================================================================

$CredFile = Join-Path $PSScriptRoot "credentials-$ResourceGroup.txt"
@"
OpenClaw on Azure - Credentials
================================
Date: $(Get-Date -Format "yyyy-MM-dd HH:mm")

=== VM ACCESS (via Bastion) ===
Resource Group: $ResourceGroup
VM Name: $VmNameOutput
Username: $AdminUsername
Password: $VmPassword

=== AZURE AI FOUNDRY ===
Endpoint: $AiFoundryEndpoint
Model: $ModelName

=== AZURE APIM ===
Gateway URL: $ApimGatewayUrl
API Path: $ApimGatewayUrl/openai
Subscription Key: $ApimKey

=== OPENCLAW ===
Gateway Password: $GatewayPassword
Dashboard: http://localhost:18789/ (via Bastion tunnel)

=== USEFUL COMMANDS ===
# Stop VM:
az vm deallocate -g $ResourceGroup -n $VmNameOutput

# Start VM:
az vm start -g $ResourceGroup -n $VmNameOutput

# Delete all:
az group delete -n $ResourceGroup --yes

=== BASTION CONNECTION ===
https://portal.azure.com → Resource Groups → $ResourceGroup → $VmNameOutput → Connect → Bastion
"@ | Out-File -FilePath $CredFile -Encoding utf8

Write-Host "📄 Credentials saved in: $CredFile" -ForegroundColor Gray
Write-Host "📄 OpenClaw config saved in: $ConfigPath" -ForegroundColor Gray
Write-Host ""
