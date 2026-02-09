#!/usr/bin/env pwsh
#
# OpenClaw on Azure with AI Foundry via APIM
# Version 4.0 - Secure deployment with Bastion + APIM + MSI
#
# This script deploys:
# - Azure VM (no public IP)
# - Azure Bastion (secure access)
# - Azure APIM (proxy for AI Foundry with MSI)
# - OpenClaw configuration ready to use
#

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroup,
    
    [Parameter(Mandatory=$true)]
    [string]$AiFoundryName,
    
    [string]$Location = "swedencentral",
    [string]$VmName = "vm-openclaw",
    [string]$AdminUsername = "azureuser"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   🦞 OpenClaw on Azure with AI Foundry (APIM + MSI) 🦞        ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "⚠️  This deployment takes approximately 15-20 minutes" -ForegroundColor Yellow
Write-Host ""

# Generate secure secrets
$VmPassword = -join ((65..90) + (97..122) + (48..57) + (33, 35, 36, 64) | Get-Random -Count 20 | ForEach-Object {[char]$_})
$GatewayToken = "openclaw-" + -join ((97..122) + (48..57) | Get-Random -Count 16 | ForEach-Object {[char]$_})
$ApimSuffix = -join ((48..57) | Get-Random -Count 4 | ForEach-Object {[char]$_})
$ApimName = "apim-openclaw-$ApimSuffix"

Write-Host "📦 Step 1/8: Creating the Resource Group..." -ForegroundColor Yellow
az group create -n $ResourceGroup -l $Location -o none

Write-Host "🌐 Step 2/8: Creating the VNet..." -ForegroundColor Yellow
az network vnet create `
    -g $ResourceGroup `
    -n "vnet-openclaw" `
    --address-prefix "10.0.0.0/16" `
    --subnet-name "default" `
    --subnet-prefix "10.0.0.0/24" `
    -o none

az network vnet subnet create `
    -g $ResourceGroup `
    --vnet-name "vnet-openclaw" `
    -n "AzureBastionSubnet" `
    --address-prefix "10.0.1.0/26" `
    -o none

Write-Host "🖥️  Step 3/8: Creating the VM (no public IP)..." -ForegroundColor Yellow
az vm create `
    -g $ResourceGroup `
    -n $VmName `
    --image Ubuntu2404 `
    --size Standard_D2s_v5 `
    --admin-username $AdminUsername `
    --admin-password $VmPassword `
    --public-ip-address "" `
    --vnet-name "vnet-openclaw" `
    --subnet "default" `
    --nsg "" `
    -o none

Write-Host "🔐 Step 4/8: Assigning Managed Identity to the VM..." -ForegroundColor Yellow
az vm identity assign -g $ResourceGroup -n $VmName -o none

Write-Host "🏰 Step 5/8: Creating Azure Bastion (5-10 min)..." -ForegroundColor Yellow
az network public-ip create `
    -g $ResourceGroup `
    -n "pip-bastion" `
    --sku Standard `
    --allocation-method Static `
    -o none

az network bastion create `
    -g $ResourceGroup `
    -n "bastion-openclaw" `
    --public-ip-address "pip-bastion" `
    --vnet-name "vnet-openclaw" `
    --sku Basic `
    -o none

Write-Host "🔌 Step 6/8: Creating Azure APIM (10-15 min)..." -ForegroundColor Yellow
az apim create `
    -g $ResourceGroup `
    -n $ApimName `
    -l $Location `
    --sku-name Consumption `
    --publisher-email "admin@openclaw.local" `
    --publisher-name "OpenClaw" `
    --enable-managed-identity `
    -o none

Write-Host "🔑 Step 7/8: Configuring permissions..." -ForegroundColor Yellow

# Get IDs
$ApimPrincipalId = az apim show -g $ResourceGroup -n $ApimName --query identity.principalId -o tsv
$AiFoundryResourceId = az cognitiveservices account show -n $AiFoundryName -g $ResourceGroup --query id -o tsv 2>$null

if (-not $AiFoundryResourceId) {
    # Try to find in another resource group
    $AiFoundryResourceId = az cognitiveservices account list --query "[?name=='$AiFoundryName'].id" -o tsv
}

if (-not $AiFoundryResourceId) {
    Write-Host "❌ AI Foundry '$AiFoundryName' not found!" -ForegroundColor Red
    exit 1
}

# Assign the role to APIM
az role assignment create `
    --assignee $ApimPrincipalId `
    --role "Cognitive Services OpenAI User" `
    --scope $AiFoundryResourceId `
    -o none 2>$null

Write-Host "⚙️  Step 8/8: Configuring the APIM API..." -ForegroundColor Yellow

$AiFoundryEndpoint = az cognitiveservices account show -n $AiFoundryName --query properties.endpoint -o tsv 2>$null
if (-not $AiFoundryEndpoint) {
    $AiFoundryEndpoint = "https://${AiFoundryName}.openai.azure.com/"
}

# Create the API
$apiBody = @{
    properties = @{
        displayName = "OpenAI Proxy"
        path = "openai"
        protocols = @("https")
        serviceUrl = $AiFoundryEndpoint.TrimEnd('/') + "/openai"
        subscriptionRequired = $false
        subscriptionKeyParameterNames = @{
            header = "api-key"
            query = "subscription-key"
        }
    }
} | ConvertTo-Json -Depth 10
$apiBody | Out-File -FilePath "$env:TEMP\api-body.json" -Encoding utf8

az rest --method PUT `
    --uri "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName/apis/openai-proxy?api-version=2023-09-01-preview" `
    --body "@$env:TEMP\api-body.json" `
    -o none

# Create the chat-completions operation
$opBody = @{
    properties = @{
        displayName = "Chat Completions"
        method = "POST"
        urlTemplate = "/deployments/{deployment-id}/chat/completions"
        templateParameters = @(
            @{ name = "deployment-id"; required = $true; type = "string" }
        )
    }
} | ConvertTo-Json -Depth 10
$opBody | Out-File -FilePath "$env:TEMP\op-body.json" -Encoding utf8

az rest --method PUT `
    --uri "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName/apis/openai-proxy/operations/chat-completions?api-version=2023-09-01-preview" `
    --body "@$env:TEMP\op-body.json" `
    -o none

# Create the policy
$policyXml = @"
<policies><inbound><base /><choose><when condition="@(!context.Request.Headers.ContainsKey(&quot;api-key&quot;) &amp;&amp; context.Request.Headers.ContainsKey(&quot;Authorization&quot;))"><set-header name="api-key" exists-action="override"><value>@{var authHeader = context.Request.Headers.GetValueOrDefault(&quot;Authorization&quot;, &quot;&quot;);if (authHeader.StartsWith(&quot;Bearer &quot;, StringComparison.OrdinalIgnoreCase)) {return authHeader.Substring(7);}return authHeader;}</value></set-header></when></choose><authentication-managed-identity resource="https://cognitiveservices.azure.com" output-token-variable-name="msi-access-token" ignore-error="false" /><set-header name="Authorization" exists-action="override"><value>@(&quot;Bearer &quot; + (string)context.Variables[&quot;msi-access-token&quot;])</value></set-header><set-backend-service base-url="${AiFoundryEndpoint}openai" /></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>
"@

$policyBody = @{ properties = @{ format = "xml"; value = $policyXml } } | ConvertTo-Json -Depth 10
$policyBody | Out-File -FilePath "$env:TEMP\policy-body.json" -Encoding utf8

az rest --method PUT `
    --uri "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName/apis/openai-proxy/operations/chat-completions/policies/policy?api-version=2023-09-01-preview" `
    --body "@$env:TEMP\policy-body.json" `
    -o none

# Get the APIM subscription key
$ApimSubscriptionKey = az rest --method POST `
    --uri "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName/subscriptions/master/listSecrets?api-version=2023-09-01-preview" `
    --query primaryKey -o tsv

$ApimEndpoint = "https://${ApimName}.azure-api.net"

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║              🎉 DEPLOYMENT COMPLETE! 🎉                        ║" -ForegroundColor Green
Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "🏰 Connection via Bastion:" -ForegroundColor Cyan
Write-Host "   Portal Azure > $ResourceGroup > $VmName > Connect > Bastion" -ForegroundColor White
Write-Host "   Username: $AdminUsername" -ForegroundColor White
Write-Host "   Password: $VmPassword" -ForegroundColor White
Write-Host ""
Write-Host "📋 OpenClaw Configuration (run on the VM):" -ForegroundColor Cyan
Write-Host ""
Write-Host "   # 1. Install Node.js and OpenClaw" -ForegroundColor Gray
Write-Host "   curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -" -ForegroundColor White
Write-Host "   sudo apt-get install -y nodejs" -ForegroundColor White
Write-Host "   sudo npm install -g openclaw" -ForegroundColor White
Write-Host ""
Write-Host "   # 2. Configure OpenClaw" -ForegroundColor Gray
Write-Host "   openclaw setup" -ForegroundColor White
Write-Host ""
Write-Host "🔧 Values for OpenClaw configuration:" -ForegroundColor Yellow
Write-Host "   APIM Endpoint: $ApimEndpoint" -ForegroundColor White
Write-Host "   APIM Key: $ApimSubscriptionKey" -ForegroundColor White
Write-Host "   Gateway Token: $GatewayToken" -ForegroundColor White
Write-Host ""

# Save credentials
$CredFile = "credentials-$ResourceGroup.txt"
@"
OpenClaw on Azure with AI Foundry - Credentials
================================================
Date: $(Get-Date -Format "yyyy-MM-dd HH:mm")

--- VM Connection (via Bastion) ---
Username: $AdminUsername
Password: $VmPassword

--- APIM (for OpenClaw) ---
Endpoint: $ApimEndpoint
Subscription Key: $ApimSubscriptionKey

--- OpenClaw Gateway ---
Token: $GatewayToken

--- OpenClaw Configuration (~/.openclaw/openclaw.json) ---
{
  "gateway": {
    "mode": "local",
    "auth": { "token": "$GatewayToken" }
  },
  "agents": {
    "defaults": {
      "workspace": "~/.openclaw/workspace",
      "model": { "primary": "azure-apim/gpt-5.2" }
    }
  },
  "models": {
    "mode": "merge",
    "providers": {
      "azure-apim": {
        "baseUrl": "$ApimEndpoint/openai/deployments/gpt-5.2",
        "apiKey": "$ApimSubscriptionKey",
        "api": "openai-completions",
        "models": [{
          "id": "gpt-5.2",
          "name": "GPT 5.2 via APIM",
          "reasoning": false,
          "input": ["text"],
          "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
          "contextWindow": 128000,
          "maxTokens": 32000
        }]
      }
    }
  }
}

--- Startup commands (on the VM) ---
# Terminal 1: Gateway
OPENCLAW_GATEWAY_TOKEN="$GatewayToken" openclaw gateway --verbose &

# Terminal 2: TUI
OPENCLAW_GATEWAY_TOKEN="$GatewayToken" openclaw

--- Cleanup ---
az group delete -n $ResourceGroup --yes
"@ | Out-File -FilePath $CredFile -Encoding utf8

Write-Host "📄 Credentials saved in: $CredFile" -ForegroundColor Gray
Write-Host ""
Write-Host "🗑️  To delete all resources:" -ForegroundColor Yellow
Write-Host "   az group delete -n $ResourceGroup --yes" -ForegroundColor White
Write-Host ""
