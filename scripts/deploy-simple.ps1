#!/usr/bin/env pwsh
#
# OpenClaw on Azure - 100% Automated Deployment
# Version 3.0 - Everything works without manual intervention
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
Write-Host "║          🦞 OpenClaw on Azure - Auto Deployment 🦞              ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Generate a secure password
$Password = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 16 | ForEach-Object {[char]$_}) + "!"
$GatewayPassword = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 12 | ForEach-Object {[char]$_}) + "!"

Write-Host "📦 Step 1/6: Creating the Resource Group..." -ForegroundColor Yellow
az group create -n $ResourceGroup -l $Location -o none

Write-Host "🔐 Step 2/6: Creating Azure OpenAI..." -ForegroundColor Yellow
az cognitiveservices account create `
    -n "ai-openclaw" `
    -g $ResourceGroup `
    -l $Location `
    --kind OpenAI `
    --sku S0 `
    --custom-domain "ai-openclaw" `
    -o none 2>$null

# Deploy the GPT-4o model
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

Write-Host "🖥️ Step 3/6: Creating the VM with cloud-init..." -ForegroundColor Yellow

# Integrated cloud-init
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

# Create the VM with public IP
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

Write-Host "🔓 Step 4/6: Configuring NSG for OpenClaw..." -ForegroundColor Yellow
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

Write-Host "🔑 Step 5/6: Configuring Azure OpenAI permissions..." -ForegroundColor Yellow
$VmPrincipalId = az vm identity assign -g $ResourceGroup -n $VmName --query systemAssignedIdentity -o tsv
$AiResourceId = az cognitiveservices account show -n "ai-openclaw" -g $ResourceGroup --query id -o tsv

az role assignment create `
    --assignee $VmPrincipalId `
    --role "Cognitive Services OpenAI User" `
    --scope $AiResourceId `
    -o none 2>$null

Write-Host "⏳ Step 6/6: Waiting for OpenClaw to start (3 minutes)..." -ForegroundColor Yellow
Start-Sleep -Seconds 180

# Retrieve the public IP
$PublicIP = az vm show -g $ResourceGroup -n $VmName -d --query publicIps -o tsv

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║              🎉 DEPLOYMENT COMPLETE! 🎉                        ║" -ForegroundColor Green
Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "🌐 OpenClaw WebChat:" -ForegroundColor Cyan
Write-Host "   http://${PublicIP}:18789" -ForegroundColor White
Write-Host ""
Write-Host "🔑 Gateway Password:" -ForegroundColor Cyan
Write-Host "   $GatewayPassword" -ForegroundColor White
Write-Host ""
Write-Host "🖥️ SSH (if needed):" -ForegroundColor Cyan
Write-Host "   ssh ${AdminUsername}@${PublicIP}" -ForegroundColor White
Write-Host "   Password: $Password" -ForegroundColor White
Write-Host ""
Write-Host "💰 To stop and save costs:" -ForegroundColor Yellow
Write-Host "   az vm deallocate -g $ResourceGroup -n $VmName" -ForegroundColor White
Write-Host ""
Write-Host "🗑️ To delete:" -ForegroundColor Yellow
Write-Host "   az group delete -n $ResourceGroup --yes" -ForegroundColor White
Write-Host ""

# Save credentials
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

Write-Host "📄 Credentials saved in: $CredFile" -ForegroundColor Gray

# Open in browser
Start-Process "http://${PublicIP}:18789"
