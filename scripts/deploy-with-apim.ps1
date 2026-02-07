#!/usr/bin/env pwsh
#
# OpenClaw on Azure with AI Foundry via APIM
# Version 4.0 - Déploiement sécurisé avec Bastion + APIM + MSI
#
# Ce script déploie:
# - Azure VM (sans IP publique)
# - Azure Bastion (accès sécurisé)
# - Azure APIM (proxy pour AI Foundry avec MSI)
# - Configuration OpenClaw prête à l'emploi
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
Write-Host "⚠️  Ce déploiement prend environ 15-20 minutes" -ForegroundColor Yellow
Write-Host ""

# Générer des secrets sécurisés
$VmPassword = -join ((65..90) + (97..122) + (48..57) + (33, 35, 36, 64) | Get-Random -Count 20 | ForEach-Object {[char]$_})
$GatewayToken = "openclaw-" + -join ((97..122) + (48..57) | Get-Random -Count 16 | ForEach-Object {[char]$_})
$ApimSuffix = -join ((48..57) | Get-Random -Count 4 | ForEach-Object {[char]$_})
$ApimName = "apim-openclaw-$ApimSuffix"

Write-Host "📦 Étape 1/8: Création du Resource Group..." -ForegroundColor Yellow
az group create -n $ResourceGroup -l $Location -o none

Write-Host "🌐 Étape 2/8: Création du VNet..." -ForegroundColor Yellow
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

Write-Host "🖥️  Étape 3/8: Création de la VM (sans IP publique)..." -ForegroundColor Yellow
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

Write-Host "🔐 Étape 4/8: Attribution Managed Identity à la VM..." -ForegroundColor Yellow
az vm identity assign -g $ResourceGroup -n $VmName -o none

Write-Host "🏰 Étape 5/8: Création d'Azure Bastion (5-10 min)..." -ForegroundColor Yellow
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

Write-Host "🔌 Étape 6/8: Création d'Azure APIM (10-15 min)..." -ForegroundColor Yellow
az apim create `
    -g $ResourceGroup `
    -n $ApimName `
    -l $Location `
    --sku-name Consumption `
    --publisher-email "admin@openclaw.local" `
    --publisher-name "OpenClaw" `
    --enable-managed-identity `
    -o none

Write-Host "🔑 Étape 7/8: Configuration des permissions..." -ForegroundColor Yellow

# Obtenir les IDs
$ApimPrincipalId = az apim show -g $ResourceGroup -n $ApimName --query identity.principalId -o tsv
$AiFoundryResourceId = az cognitiveservices account show -n $AiFoundryName -g $ResourceGroup --query id -o tsv 2>$null

if (-not $AiFoundryResourceId) {
    # Essayer de trouver dans un autre resource group
    $AiFoundryResourceId = az cognitiveservices account list --query "[?name=='$AiFoundryName'].id" -o tsv
}

if (-not $AiFoundryResourceId) {
    Write-Host "❌ AI Foundry '$AiFoundryName' non trouvé!" -ForegroundColor Red
    exit 1
}

# Assigner le rôle à APIM
az role assignment create `
    --assignee $ApimPrincipalId `
    --role "Cognitive Services OpenAI User" `
    --scope $AiFoundryResourceId `
    -o none 2>$null

Write-Host "⚙️  Étape 8/8: Configuration de l'API APIM..." -ForegroundColor Yellow

$AiFoundryEndpoint = az cognitiveservices account show -n $AiFoundryName --query properties.endpoint -o tsv 2>$null
if (-not $AiFoundryEndpoint) {
    $AiFoundryEndpoint = "https://${AiFoundryName}.openai.azure.com/"
}

# Créer l'API
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

# Créer l'opération chat-completions
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

# Créer la policy
$policyXml = @"
<policies><inbound><base /><choose><when condition="@(!context.Request.Headers.ContainsKey(&quot;api-key&quot;) &amp;&amp; context.Request.Headers.ContainsKey(&quot;Authorization&quot;))"><set-header name="api-key" exists-action="override"><value>@{var authHeader = context.Request.Headers.GetValueOrDefault(&quot;Authorization&quot;, &quot;&quot;);if (authHeader.StartsWith(&quot;Bearer &quot;, StringComparison.OrdinalIgnoreCase)) {return authHeader.Substring(7);}return authHeader;}</value></set-header></when></choose><authentication-managed-identity resource="https://cognitiveservices.azure.com" output-token-variable-name="msi-access-token" ignore-error="false" /><set-header name="Authorization" exists-action="override"><value>@(&quot;Bearer &quot; + (string)context.Variables[&quot;msi-access-token&quot;])</value></set-header><set-backend-service base-url="${AiFoundryEndpoint}openai" /></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>
"@

$policyBody = @{ properties = @{ format = "xml"; value = $policyXml } } | ConvertTo-Json -Depth 10
$policyBody | Out-File -FilePath "$env:TEMP\policy-body.json" -Encoding utf8

az rest --method PUT `
    --uri "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName/apis/openai-proxy/operations/chat-completions/policies/policy?api-version=2023-09-01-preview" `
    --body "@$env:TEMP\policy-body.json" `
    -o none

# Obtenir la subscription key APIM
$ApimSubscriptionKey = az rest --method POST `
    --uri "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName/subscriptions/master/listSecrets?api-version=2023-09-01-preview" `
    --query primaryKey -o tsv

$ApimEndpoint = "https://${ApimName}.azure-api.net"

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║              🎉 DÉPLOIEMENT TERMINÉ ! 🎉                       ║" -ForegroundColor Green
Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "🏰 Connexion via Bastion:" -ForegroundColor Cyan
Write-Host "   Portal Azure > $ResourceGroup > $VmName > Connect > Bastion" -ForegroundColor White
Write-Host "   Username: $AdminUsername" -ForegroundColor White
Write-Host "   Password: $VmPassword" -ForegroundColor White
Write-Host ""
Write-Host "📋 Configuration OpenClaw (à exécuter sur la VM):" -ForegroundColor Cyan
Write-Host ""
Write-Host "   # 1. Installer Node.js et OpenClaw" -ForegroundColor Gray
Write-Host "   curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -" -ForegroundColor White
Write-Host "   sudo apt-get install -y nodejs" -ForegroundColor White
Write-Host "   sudo npm install -g openclaw" -ForegroundColor White
Write-Host ""
Write-Host "   # 2. Configurer OpenClaw" -ForegroundColor Gray
Write-Host "   openclaw setup" -ForegroundColor White
Write-Host ""
Write-Host "🔧 Valeurs pour la configuration OpenClaw:" -ForegroundColor Yellow
Write-Host "   APIM Endpoint: $ApimEndpoint" -ForegroundColor White
Write-Host "   APIM Key: $ApimSubscriptionKey" -ForegroundColor White
Write-Host "   Gateway Token: $GatewayToken" -ForegroundColor White
Write-Host ""

# Sauvegarder les credentials
$CredFile = "credentials-$ResourceGroup.txt"
@"
OpenClaw on Azure with AI Foundry - Credentials
================================================
Date: $(Get-Date -Format "yyyy-MM-dd HH:mm")

--- Connexion VM (via Bastion) ---
Username: $AdminUsername
Password: $VmPassword

--- APIM (pour OpenClaw) ---
Endpoint: $ApimEndpoint
Subscription Key: $ApimSubscriptionKey

--- OpenClaw Gateway ---
Token: $GatewayToken

--- Configuration OpenClaw (~/.openclaw/openclaw.json) ---
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

--- Commandes de démarrage (sur la VM) ---
# Terminal 1: Gateway
OPENCLAW_GATEWAY_TOKEN="$GatewayToken" openclaw gateway --verbose &

# Terminal 2: TUI
OPENCLAW_GATEWAY_TOKEN="$GatewayToken" openclaw

--- Nettoyage ---
az group delete -n $ResourceGroup --yes
"@ | Out-File -FilePath $CredFile -Encoding utf8

Write-Host "📄 Credentials sauvegardés dans: $CredFile" -ForegroundColor Gray
Write-Host ""
Write-Host "🗑️  Pour supprimer toutes les ressources:" -ForegroundColor Yellow
Write-Host "   az group delete -n $ResourceGroup --yes" -ForegroundColor White
Write-Host ""
