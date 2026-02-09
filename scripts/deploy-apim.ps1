#!/usr/bin/env pwsh
#
# OpenClaw on Azure - Déploiement complet avec APIM
# Installation native + Azure AI Foundry + APIM
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
Write-Host "║     🦞 OpenClaw on Azure - Déploiement avec APIM 🦞           ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# Vérification des prérequis
# =============================================================================

Write-Host "🔍 Vérification des prérequis..." -ForegroundColor Yellow

# Vérifier Azure CLI
try {
    $azCmd = Get-Command az -ErrorAction Stop
    Write-Host "   ✅ Azure CLI trouvé: $($azCmd.Source)" -ForegroundColor Green
} catch {
    Write-Host "❌ Azure CLI non installé. Installez-le depuis https://aka.ms/installazurecliwindows" -ForegroundColor Red
    exit 1
}

# Vérifier connexion Azure
$account = az account show --query name -o tsv 2>$null
if (-not $account) {
    Write-Host "⚠️ Non connecté à Azure. Connexion en cours..." -ForegroundColor Yellow
    az login
    $account = az account show --query name -o tsv
}
Write-Host "   ✅ Connecté à: $account" -ForegroundColor Green

# =============================================================================
# Générer les mots de passe
# =============================================================================

$VmPassword = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 16 | ForEach-Object {[char]$_}) + "!Aa1"
$GatewayPassword = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 12 | ForEach-Object {[char]$_}) + "!"

# =============================================================================
# Étape 1: Créer le Resource Group
# =============================================================================

Write-Host ""
Write-Host "📦 Étape 1/6: Création du Resource Group..." -ForegroundColor Yellow
az group create -n $ResourceGroup -l $Location -o none
Write-Host "   ✅ Resource Group '$ResourceGroup' créé" -ForegroundColor Green

# =============================================================================
# Étape 2: Déployer l'infrastructure Bicep
# =============================================================================

Write-Host ""
Write-Host "🏗️ Étape 2/6: Déploiement de l'infrastructure (VM + AI + APIM + Bastion)..." -ForegroundColor Yellow
Write-Host "   ⏳ Cette étape peut prendre 15-20 minutes..." -ForegroundColor Gray

$bicepPath = Join-Path $PSScriptRoot "..\infra\main-apim.bicep"

# Vérifier que le fichier Bicep existe
if (-not (Test-Path $bicepPath)) {
    Write-Host "❌ Fichier Bicep non trouvé: $bicepPath" -ForegroundColor Red
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
    Write-Host "❌ Échec du déploiement Bicep" -ForegroundColor Red
    exit 1
}

$VmNameOutput = $deploymentResult.vmName.value
$ApimGatewayUrl = $deploymentResult.apimGatewayUrl.value
$ApimName = $deploymentResult.apimName.value
$AiFoundryEndpoint = $deploymentResult.aiFoundryEndpoint.value
$BastionName = $deploymentResult.bastionName.value

Write-Host "   ✅ Infrastructure déployée" -ForegroundColor Green

# =============================================================================
# Étape 3: Récupérer la clé APIM
# =============================================================================

Write-Host ""
Write-Host "🔑 Étape 3/6: Récupération de la clé APIM..." -ForegroundColor Yellow

$ApimKey = az rest --method post `
    --uri "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName/subscriptions/openclaw-subscription/listSecrets?api-version=2024-05-01" `
    --query "primaryKey" -o tsv

if (-not $ApimKey) {
    Write-Host "⚠️ Impossible de récupérer la clé APIM. Récupération manuelle requise." -ForegroundColor Yellow
    $ApimKey = "RECUPERER_MANUELLEMENT"
}

Write-Host "   ✅ Clé APIM récupérée" -ForegroundColor Green

# =============================================================================
# Étape 4: Configurer OpenClaw sur la VM (via Bastion/Serial Console)
# =============================================================================

Write-Host ""
Write-Host "⚙️ Étape 4/6: Attente de la configuration de la VM (5 minutes)..." -ForegroundColor Yellow
Write-Host "   ⏳ Cloud-init installe Node.js et OpenClaw..." -ForegroundColor Gray
Start-Sleep -Seconds 300

# =============================================================================
# Étape 5: Créer le fichier de configuration OpenClaw
# =============================================================================

Write-Host ""
Write-Host "📝 Étape 5/6: Préparation de la configuration OpenClaw..." -ForegroundColor Yellow

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

# Sauvegarder la config localement
$ConfigPath = Join-Path $PSScriptRoot "openclaw-config-$ResourceGroup.json"
$OpenClawConfig | Out-File -FilePath $ConfigPath -Encoding utf8

Write-Host "   ✅ Configuration OpenClaw sauvegardée: $ConfigPath" -ForegroundColor Green

# =============================================================================
# Étape 6: Résumé final
# =============================================================================

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║              🎉 DÉPLOIEMENT TERMINÉ ! 🎉                       ║" -ForegroundColor Green
Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

Write-Host "🖥️ ACCÈS À LA VM (via Bastion):" -ForegroundColor Cyan
Write-Host "   1. Allez sur https://portal.azure.com" -ForegroundColor White
Write-Host "   2. Resource Groups → $ResourceGroup → $VmNameOutput" -ForegroundColor White
Write-Host "   3. Cliquez 'Connect' → 'Bastion'" -ForegroundColor White
Write-Host "   4. Username: $AdminUsername" -ForegroundColor White
Write-Host "   5. Password: $VmPassword" -ForegroundColor White
Write-Host ""

Write-Host "⚙️ CONFIGURATION OPENCLAW (à exécuter sur la VM):" -ForegroundColor Cyan
Write-Host "   1. Copiez le fichier de config dans la VM:" -ForegroundColor White
Write-Host "      cat > ~/.openclaw/openclaw.json << 'EOF'" -ForegroundColor Gray
Write-Host "      $OpenClawConfig" -ForegroundColor Gray
Write-Host "      EOF" -ForegroundColor Gray
Write-Host ""
Write-Host "   2. Lancez l'onboarding:" -ForegroundColor White
Write-Host "      openclaw onboard --install-daemon" -ForegroundColor Gray
Write-Host ""
Write-Host "   3. Ou démarrez manuellement:" -ForegroundColor White
Write-Host "      ./start.sh" -ForegroundColor Gray
Write-Host ""

Write-Host "🔑 CREDENTIALS:" -ForegroundColor Cyan
Write-Host "   Gateway Password: $GatewayPassword" -ForegroundColor White
Write-Host "   APIM Key: $ApimKey" -ForegroundColor White
Write-Host "   APIM Endpoint: $ApimGatewayUrl/openai" -ForegroundColor White
Write-Host ""

Write-Host "🤖 MODÈLES CONFIGURÉS:" -ForegroundColor Cyan
Write-Host "   - $ModelName (principal)" -ForegroundColor White
Write-Host "   - gpt-5.2 (fallback)" -ForegroundColor White
Write-Host "   - gpt-4o (fallback)" -ForegroundColor White
Write-Host ""

Write-Host "💰 POUR ÉCONOMISER:" -ForegroundColor Yellow
Write-Host "   Arrêter la VM:" -ForegroundColor White
Write-Host "   az vm deallocate -g $ResourceGroup -n $VmNameOutput" -ForegroundColor Gray
Write-Host ""
Write-Host "   Redémarrer la VM:" -ForegroundColor White
Write-Host "   az vm start -g $ResourceGroup -n $VmNameOutput" -ForegroundColor Gray
Write-Host ""

Write-Host "🗑️ POUR SUPPRIMER:" -ForegroundColor Yellow
Write-Host "   az group delete -n $ResourceGroup --yes --no-wait" -ForegroundColor Gray
Write-Host ""

# =============================================================================
# Sauvegarder les credentials
# =============================================================================

$CredFile = Join-Path $PSScriptRoot "credentials-$ResourceGroup.txt"
@"
OpenClaw on Azure - Credentials
================================
Date: $(Get-Date -Format "yyyy-MM-dd HH:mm")

=== ACCÈS VM (via Bastion) ===
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

=== COMMANDES UTILES ===
# Arrêter VM:
az vm deallocate -g $ResourceGroup -n $VmNameOutput

# Démarrer VM:
az vm start -g $ResourceGroup -n $VmNameOutput

# Supprimer tout:
az group delete -n $ResourceGroup --yes

=== CONNEXION BASTION ===
https://portal.azure.com → Resource Groups → $ResourceGroup → $VmNameOutput → Connect → Bastion
"@ | Out-File -FilePath $CredFile -Encoding utf8

Write-Host "📄 Credentials sauvegardés dans: $CredFile" -ForegroundColor Gray
Write-Host "📄 Config OpenClaw sauvegardée dans: $ConfigPath" -ForegroundColor Gray
Write-Host ""
