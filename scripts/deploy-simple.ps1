#!/usr/bin/env pwsh
#
# OpenClaw on Azure - Déploiement 100% automatisé
# Version 3.0 - Tout fonctionne sans intervention manuelle
#

param(
    [string]$ResourceGroup = "rg-openclaw",
    [string]$Location = "swedencentral",
    [string]$VmName = "vm-openclaw",
    [string]$AdminUsername = "azureuser"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║          🦞 OpenClaw on Azure - Déploiement Auto 🦞            ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Générer un mot de passe sécurisé
$Password = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 16 | ForEach-Object {[char]$_}) + "!"
$GatewayPassword = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 12 | ForEach-Object {[char]$_}) + "!"

Write-Host "📦 Étape 1/6: Création du Resource Group..." -ForegroundColor Yellow
az group create -n $ResourceGroup -l $Location -o none

Write-Host "🔐 Étape 2/6: Création d'Azure OpenAI..." -ForegroundColor Yellow
az cognitiveservices account create `
    -n "ai-openclaw" `
    -g $ResourceGroup `
    -l $Location `
    --kind OpenAI `
    --sku S0 `
    --custom-domain "ai-openclaw" `
    -o none 2>$null

# Déployer le modèle GPT-4o
az cognitiveservices account deployment create `
    -n "ai-openclaw" `
    -g $ResourceGroup `
    --deployment-name "gpt-4o" `
    --model-name "gpt-4o" `
    --model-version "2024-08-06" `
    --model-format OpenAI `
    --sku-capacity 10 `
    --sku-name "GlobalStandard" `
    -o none 2>$null

$AiEndpoint = "https://ai-openclaw.openai.azure.com/"

Write-Host "🖥️ Étape 3/6: Création de la VM avec cloud-init..." -ForegroundColor Yellow

# Cloud-init intégré
$CloudInit = @"
#cloud-config
package_update: true
packages:
  - curl
  - git
  - jq

runcmd:
  - curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  - apt-get install -y nodejs
  - npm install -g pnpm
  - git clone https://github.com/openclaw/openclaw.git /home/$AdminUsername/openclaw
  - cd /home/$AdminUsername/openclaw && pnpm install
  - mkdir -p /home/$AdminUsername/openclaw/data
  - |
    cat > /home/$AdminUsername/openclaw/.env << 'ENVEOF'
    OPENCLAW_GATEWAY_PASSWORD=$GatewayPassword
    OPENCLAW_TLS_ENABLED=false
    AZURE_OPENAI_ENDPOINT=$AiEndpoint
    AZURE_OPENAI_DEPLOYMENT=gpt-4o
    AZURE_OPENAI_API_VERSION=2024-10-01-preview
    PORT=18789
    ENVEOF
  - chown -R $AdminUsername`:$AdminUsername /home/$AdminUsername/openclaw
  - echo "$GatewayPassword" > /home/$AdminUsername/openclaw/password.txt
  - chown $AdminUsername`:$AdminUsername /home/$AdminUsername/openclaw/password.txt
  - cd /home/$AdminUsername/openclaw && npx openclaw gateway start

final_message: "OpenClaw ready!"
"@

$CloudInitPath = "$env:TEMP\cloud-init-openclaw.yaml"
$CloudInit | Out-File -FilePath $CloudInitPath -Encoding utf8 -Force

# Créer la VM avec IP publique
az vm create `
    -g $ResourceGroup `
    -n $VmName `
    --image Ubuntu2404 `
    --size Standard_D2s_v5 `
    --admin-username $AdminUsername `
    --admin-password $Password `
    --public-ip-sku Standard `
    --custom-data $CloudInitPath `
    --nsg-rule SSH `
    -o none

Write-Host "🔓 Étape 4/6: Configuration du NSG pour OpenClaw..." -ForegroundColor Yellow
$NsgName = "${VmName}NSG"
az network nsg rule create `
    --nsg-name $NsgName `
    -g $ResourceGroup `
    -n AllowOpenClaw `
    --priority 1001 `
    --access Allow `
    --protocol Tcp `
    --destination-port-ranges 18789 `
    -o none

Write-Host "🔑 Étape 5/6: Configuration des permissions Azure OpenAI..." -ForegroundColor Yellow
$VmPrincipalId = az vm identity assign -g $ResourceGroup -n $VmName --query systemAssignedIdentity -o tsv
$AiResourceId = az cognitiveservices account show -n "ai-openclaw" -g $ResourceGroup --query id -o tsv

az role assignment create `
    --assignee $VmPrincipalId `
    --role "Cognitive Services OpenAI User" `
    --scope $AiResourceId `
    -o none 2>$null

Write-Host "⏳ Étape 6/6: Attente du démarrage d'OpenClaw (3 minutes)..." -ForegroundColor Yellow
Start-Sleep -Seconds 180

# Récupérer l'IP publique
$PublicIP = az vm show -g $ResourceGroup -n $VmName -d --query publicIps -o tsv

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║              🎉 DÉPLOIEMENT TERMINÉ ! 🎉                       ║" -ForegroundColor Green
Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "🌐 OpenClaw WebChat:" -ForegroundColor Cyan
Write-Host "   http://${PublicIP}:18789" -ForegroundColor White
Write-Host ""
Write-Host "🔑 Mot de passe Gateway:" -ForegroundColor Cyan
Write-Host "   $GatewayPassword" -ForegroundColor White
Write-Host ""
Write-Host "🖥️ SSH (si besoin):" -ForegroundColor Cyan
Write-Host "   ssh ${AdminUsername}@${PublicIP}" -ForegroundColor White
Write-Host "   Password: $Password" -ForegroundColor White
Write-Host ""
Write-Host "💰 Pour arrêter et économiser:" -ForegroundColor Yellow
Write-Host "   az vm deallocate -g $ResourceGroup -n $VmName" -ForegroundColor White
Write-Host ""
Write-Host "🗑️ Pour supprimer:" -ForegroundColor Yellow
Write-Host "   az group delete -n $ResourceGroup --yes" -ForegroundColor White
Write-Host ""

# Sauvegarder les credentials
$CredFile = "credentials-$ResourceGroup.txt"
@"
OpenClaw on Azure - Credentials
================================
Date: $(Get-Date -Format "yyyy-MM-dd HH:mm")

OpenClaw URL: http://${PublicIP}:18789
Gateway Password: $GatewayPassword

SSH: ssh ${AdminUsername}@${PublicIP}
SSH Password: $Password

Azure OpenAI Endpoint: $AiEndpoint
Model Deployment: gpt-4o

Resource Group: $ResourceGroup
VM Name: $VmName
"@ | Out-File -FilePath $CredFile -Encoding utf8

Write-Host "📄 Credentials sauvegardés dans: $CredFile" -ForegroundColor Gray

# Ouvrir dans le navigateur
Start-Process "http://${PublicIP}:18789"
