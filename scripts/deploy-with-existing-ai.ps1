#!/usr/bin/env pwsh
#
# OpenClaw on Azure - Utilise un AI Foundry EXISTANT
# Déploie VM + APIM + Bastion et connecte à votre AI Foundry
#

param(
    [Parameter(Mandatory=$true)]
    [string]$AiFoundryEndpoint,  # Ex: https://votre-nom.openai.azure.com/
    
    [Parameter(Mandatory=$true)]
    [string]$AiFoundryResourceId,  # Ex: /subscriptions/.../resourceGroups/.../providers/Microsoft.CognitiveServices/accounts/...
    
    [string]$ResourceGroup = "rg-openclaw",
    [string]$Location = "swedencentral",
    [string]$AdminUsername = "azureuser",
    [string]$ModelDeploymentName = "gpt-5.2-codex",
    [string]$PublisherEmail = "admin@contoso.com"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  🦞 OpenClaw - Utilise AI Foundry existant 🦞                 ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# Générer les mots de passe
# =============================================================================

$VmPassword = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 16 | ForEach-Object {[char]$_}) + "!Aa1"
$GatewayPassword = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 12 | ForEach-Object {[char]$_}) + "!"

Write-Host "🔍 Configuration:" -ForegroundColor Yellow
Write-Host "   AI Foundry Endpoint: $AiFoundryEndpoint" -ForegroundColor White
Write-Host "   Model Deployment: $ModelDeploymentName" -ForegroundColor White
Write-Host "   Resource Group: $ResourceGroup" -ForegroundColor White
Write-Host ""

# =============================================================================
# Étape 1: Créer le Resource Group
# =============================================================================

Write-Host "📦 Étape 1/5: Création du Resource Group..." -ForegroundColor Yellow
az group create -n $ResourceGroup -l $Location -o none 2>$null
Write-Host "   ✅ Resource Group '$ResourceGroup' créé" -ForegroundColor Green

# =============================================================================
# Variables
# =============================================================================

$uniqueSuffix = (Get-Random -Maximum 9999).ToString("D4")
$apimName = "apim-openclaw-$uniqueSuffix"
$vmName = "vm-openclaw"
$vnetName = "vnet-openclaw"
$bastionName = "bastion-openclaw"

# =============================================================================
# Étape 2: Créer le VNet et Bastion
# =============================================================================

Write-Host ""
Write-Host "🌐 Étape 2/5: Création du réseau (VNet + Bastion)..." -ForegroundColor Yellow
Write-Host "   ⏳ Bastion prend ~5 minutes..." -ForegroundColor Gray

# Créer le VNet
az network vnet create `
    -g $ResourceGroup `
    -n $vnetName `
    --address-prefix "10.0.0.0/16" `
    --subnet-name "default" `
    --subnet-prefix "10.0.0.0/24" `
    -o none

# Créer le subnet Bastion
az network vnet subnet create `
    -g $ResourceGroup `
    --vnet-name $vnetName `
    -n "AzureBastionSubnet" `
    --address-prefix "10.0.1.0/26" `
    -o none

# Créer l'IP publique pour Bastion
az network public-ip create `
    -g $ResourceGroup `
    -n "pip-$bastionName" `
    --sku Standard `
    --allocation-method Static `
    -o none

# Créer Bastion
az network bastion create `
    -g $ResourceGroup `
    -n $bastionName `
    --public-ip-address "pip-$bastionName" `
    --vnet-name $vnetName `
    --sku Basic `
    -o none

Write-Host "   ✅ Réseau créé" -ForegroundColor Green

# =============================================================================
# Étape 3: Créer APIM
# =============================================================================

Write-Host ""
Write-Host "🔌 Étape 3/5: Création d'Azure API Management..." -ForegroundColor Yellow
Write-Host "   ⏳ APIM Consumption prend ~2 minutes..." -ForegroundColor Gray

az apim create `
    -g $ResourceGroup `
    -n $apimName `
    --publisher-email $PublisherEmail `
    --publisher-name "OpenClaw Admin" `
    --sku-name Consumption `
    -o none

# Activer Managed Identity sur APIM
az apim update -g $ResourceGroup -n $apimName --enable-managed-identity true -o none

$apimPrincipalId = az apim show -g $ResourceGroup -n $apimName --query "identity.principalId" -o tsv
$apimGatewayUrl = az apim show -g $ResourceGroup -n $apimName --query "gatewayUrl" -o tsv

Write-Host "   ✅ APIM créé: $apimGatewayUrl" -ForegroundColor Green

# =============================================================================
# Étape 3b: Donner accès APIM à AI Foundry
# =============================================================================

Write-Host ""
Write-Host "🔑 Attribution des permissions APIM → AI Foundry..." -ForegroundColor Yellow

az role assignment create `
    --assignee $apimPrincipalId `
    --role "Cognitive Services OpenAI User" `
    --scope $AiFoundryResourceId `
    -o none 2>$null

Write-Host "   ✅ Permissions attribuées" -ForegroundColor Green

# =============================================================================
# Étape 3c: Configurer l'API dans APIM
# =============================================================================

Write-Host ""
Write-Host "⚙️ Configuration de l'API OpenAI dans APIM..." -ForegroundColor Yellow

# Créer l'API
az apim api create `
    -g $ResourceGroup `
    --service-name $apimName `
    --api-id "openai-proxy" `
    --path "openai" `
    --display-name "Azure OpenAI Proxy" `
    --service-url "${AiFoundryEndpoint}openai" `
    --protocols https `
    --subscription-required true `
    -o none

# Créer une opération catch-all
az apim api operation create `
    -g $ResourceGroup `
    --service-name $apimName `
    --api-id "openai-proxy" `
    --operation-id "all-ops" `
    --display-name "All Operations" `
    --method "*" `
    --url-template "/*" `
    -o none

# Appliquer la policy pour transformer la clé en token MSI
$policy = @'
<policies>
  <inbound>
    <base />
    <set-header name="api-key" exists-action="delete" />
    <authentication-managed-identity resource="https://cognitiveservices.azure.com" output-token-variable-name="msi-access-token" ignore-error="false" />
    <set-header name="Authorization" exists-action="override">
      <value>@("Bearer " + (string)context.Variables["msi-access-token"])</value>
    </set-header>
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'@

$policyFile = "$env:TEMP\apim-policy.xml"
$policy | Out-File -FilePath $policyFile -Encoding utf8

az apim api policy create `
    -g $ResourceGroup `
    --service-name $apimName `
    --api-id "openai-proxy" `
    --policy-format xml `
    --policy-content "@$policyFile" `
    -o none

# Créer une subscription
az apim subscription create `
    -g $ResourceGroup `
    --service-name $apimName `
    --subscription-id "openclaw-sub" `
    --display-name "OpenClaw Subscription" `
    --scope "/apis/openai-proxy" `
    --state active `
    -o none

# Récupérer la clé
$apimKey = az apim subscription keys list `
    -g $ResourceGroup `
    --service-name $apimName `
    --subscription-id "openclaw-sub" `
    --query "primaryKey" -o tsv

Write-Host "   ✅ API configurée" -ForegroundColor Green

# =============================================================================
# Étape 4: Créer la VM
# =============================================================================

Write-Host ""
Write-Host "🖥️ Étape 4/5: Création de la VM avec OpenClaw..." -ForegroundColor Yellow

# Cloud-init pour installer OpenClaw
$cloudInit = @"
#cloud-config
package_update: true
package_upgrade: true

packages:
  - curl
  - git
  - jq

runcmd:
  - curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  - apt-get install -y nodejs
  - npm install -g openclaw@latest
  - mkdir -p /home/$AdminUsername/.openclaw
  - chown -R ${AdminUsername}:${AdminUsername} /home/$AdminUsername/.openclaw
  - echo "OpenClaw installed!" > /home/$AdminUsername/READY.txt
  - chown ${AdminUsername}:${AdminUsername} /home/$AdminUsername/READY.txt

write_files:
  - path: /home/$AdminUsername/start.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      echo "Starting OpenClaw Gateway..."
      openclaw gateway --port 18789 &
      echo "Gateway started on http://localhost:18789/"

  - path: /home/$AdminUsername/stop.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      pkill -f "openclaw gateway" || true
      echo "Gateway stopped"

  - path: /home/$AdminUsername/status.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      openclaw gateway status 2>/dev/null || echo "Gateway not running"
      openclaw health 2>/dev/null || true

  - path: /etc/motd
    permissions: '0644'
    content: |
      ╔═══════════════════════════════════════════════════════════════╗
      ║              🦞 OpenClaw on Azure 🦞                          ║
      ╠═══════════════════════════════════════════════════════════════╣
      ║  ./start.sh   - Start OpenClaw                                ║
      ║  ./stop.sh    - Stop OpenClaw                                 ║
      ║  ./status.sh  - Check status                                  ║
      ║  openclaw onboard - Run setup wizard                          ║
      ╚═══════════════════════════════════════════════════════════════╝

final_message: "OpenClaw ready!"
"@

$cloudInitFile = "$env:TEMP\cloud-init-openclaw.yaml"
$cloudInit | Out-File -FilePath $cloudInitFile -Encoding utf8

# Créer la VM sans IP publique
az vm create `
    -g $ResourceGroup `
    -n $vmName `
    --image Ubuntu2204 `
    --size Standard_D2s_v5 `
    --admin-username $AdminUsername `
    --admin-password $VmPassword `
    --vnet-name $vnetName `
    --subnet "default" `
    --public-ip-address "" `
    --custom-data $cloudInitFile `
    -o none

Write-Host "   ✅ VM créée" -ForegroundColor Green

# =============================================================================
# Étape 5: Préparer la configuration OpenClaw
# =============================================================================

Write-Host ""
Write-Host "📝 Étape 5/5: Génération de la configuration..." -ForegroundColor Yellow

$openclawConfig = @"
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "azure-openai/$ModelDeploymentName",
        "fallbacks": ["azure-openai/gpt-5.2", "azure-openai/gpt-4o"]
      },
      "models": {
        "azure-openai/$ModelDeploymentName": { "alias": "Codex" },
        "azure-openai/gpt-5.2": { "alias": "GPT-5.2" },
        "azure-openai/gpt-4o": { "alias": "GPT-4o" }
      }
    }
  },
  "models": {
    "mode": "merge",
    "providers": {
      "azure-openai": {
        "baseUrl": "$apimGatewayUrl/openai",
        "apiKey": "$apimKey",
        "api": "openai-completions",
        "models": [
          { "id": "$ModelDeploymentName", "name": "GPT-5.2 Codex", "reasoning": true },
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

$configFile = Join-Path $PSScriptRoot "openclaw-config-$ResourceGroup.json"
$openclawConfig | Out-File -FilePath $configFile -Encoding utf8

Write-Host "   ✅ Configuration générée" -ForegroundColor Green

# =============================================================================
# Résumé
# =============================================================================

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║              🎉 DÉPLOIEMENT TERMINÉ ! 🎉                       ║" -ForegroundColor Green
Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

Write-Host "🖥️ CONNEXION VM (via Bastion):" -ForegroundColor Cyan
Write-Host "   1. Portal Azure → Resource Groups → $ResourceGroup → $vmName" -ForegroundColor White
Write-Host "   2. Connect → Bastion" -ForegroundColor White
Write-Host "   3. Username: $AdminUsername" -ForegroundColor White
Write-Host "   4. Password: $VmPassword" -ForegroundColor White
Write-Host ""

Write-Host "⚙️ CONFIGURATION (sur la VM):" -ForegroundColor Cyan
Write-Host "   Copiez ce contenu dans ~/.openclaw/openclaw.json :" -ForegroundColor White
Write-Host ""
Write-Host $openclawConfig -ForegroundColor Gray
Write-Host ""

Write-Host "🚀 DÉMARRAGE:" -ForegroundColor Cyan
Write-Host "   openclaw onboard --install-daemon" -ForegroundColor Gray
Write-Host "   # ou" -ForegroundColor Gray
Write-Host "   ./start.sh" -ForegroundColor Gray
Write-Host ""

Write-Host "🔑 CREDENTIALS:" -ForegroundColor Cyan
Write-Host "   Gateway Password: $GatewayPassword" -ForegroundColor White
Write-Host "   APIM Key: $apimKey" -ForegroundColor White
Write-Host "   APIM URL: $apimGatewayUrl/openai" -ForegroundColor White
Write-Host ""

# Sauvegarder
$credFile = Join-Path $PSScriptRoot "credentials-$ResourceGroup.txt"
@"
OpenClaw Deployment - $(Get-Date -Format "yyyy-MM-dd HH:mm")
============================================================

VM ACCESS (via Bastion):
  Resource Group: $ResourceGroup
  VM: $vmName
  Username: $AdminUsername
  Password: $VmPassword

APIM:
  Gateway URL: $apimGatewayUrl
  API Path: $apimGatewayUrl/openai
  Key: $apimKey

AI FOUNDRY:
  Endpoint: $AiFoundryEndpoint
  Model: $ModelDeploymentName

OPENCLAW:
  Gateway Password: $GatewayPassword
  Config file: $configFile

COMMANDS:
  Stop VM: az vm deallocate -g $ResourceGroup -n $vmName
  Start VM: az vm start -g $ResourceGroup -n $vmName
  Delete all: az group delete -n $ResourceGroup --yes
"@ | Out-File -FilePath $credFile -Encoding utf8

Write-Host "📄 Credentials: $credFile" -ForegroundColor Gray
Write-Host "📄 Config: $configFile" -ForegroundColor Gray
