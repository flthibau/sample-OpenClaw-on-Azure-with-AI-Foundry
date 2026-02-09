# OpenClaw on Azure with APIM - Deployment Guide

This guide explains how to deploy OpenClaw on Azure with Azure API Management to solve the Entra ID authentication issue.

## 🎯 Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              Azure                                       │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │                    Virtual Network (10.0.0.0/16)                 │    │
│  │  ┌───────────────────┐  ┌──────────────────────────────────┐    │    │
│  │  │ AzureBastionSubnet │  │      Default Subnet              │    │    │
│  │  │   10.0.1.0/26     │  │       10.0.0.0/24                │    │    │
│  │  │                   │  │                                   │    │    │
│  │  │  ┌─────────────┐  │  │   ┌──────────────────────────┐   │    │    │
│  │  │  │   Azure     │  │  │   │      Linux VM            │   │    │    │
│  │  │  │   Bastion   │──┼──┼──▶│  (OpenClaw native)       │   │    │    │
│  │  │  └─────────────┘  │  │   │  Node.js 22 + OpenClaw   │   │    │    │
│  │  └───────────────────┘  │   └──────────────────────────┘   │    │    │
│  │                         └──────────────────────────────────┘    │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                    │                                     │
│                                    │ HTTPS (APIM API key)                │
│                                    ▼                                     │
│                    ┌──────────────────────────────────┐                  │
│                    │       Azure APIM                  │                  │
│                    │  ┌─────────────────────────────┐ │                  │
│                    │  │ Policy: subscription-key    │ │                  │
│                    │  │ → Bearer Token (MSI)        │ │                  │
│                    │  └─────────────────────────────┘ │                  │
│                    └──────────────┬───────────────────┘                  │
│                                   │ HTTPS (Managed Identity)             │
│                                   ▼                                     │
│                    ┌──────────────────────────────────┐                  │
│                    │       Azure AI Foundry           │                  │
│                    │  ┌─────────────────────────────┐ │                  │
│                    │  │ GPT-5.2-codex              │ │                  │
│                    │  │ (Entra ID auth only)       │ │                  │
│                    │  └─────────────────────────────┘ │                  │
│                    └──────────────────────────────────┘                  │
└─────────────────────────────────────────────────────────────────────────┘
```

## 🚀 Quick Start Deployment

### Prerequisites

- Azure subscription with access to GPT-5.2-codex
- Azure CLI installed
- PowerShell 7+

### Deploy

```powershell
# Clone the repository
cd sample-OpenClaw-on-Azure-with-AI-Foundry

# Deploy (15-20 minutes)
./scripts/deploy-apim.ps1 -ResourceGroup "rg-openclaw"
```

### Optional Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-ResourceGroup` | `rg-openclaw` | Resource Group name |
| `-Location` | `swedencentral` | Azure region |
| `-ModelName` | `gpt-5.2-codex` | Model to deploy |
| `-ModelVersion` | `2026-01-01` | Model version |
| `-PublisherEmail` | `admin@contoso.com` | Email for APIM |

## 📋 Post-Deployment

### 1. Connect to the VM via Bastion

1. Go to [portal.azure.com](https://portal.azure.com)
2. Resource Groups → your RG → your VM
3. Click **Connect** → **Bastion**
4. Enter the credentials displayed by the script

### 2. Configure OpenClaw

The deployment script generates an `openclaw-config-*.json` file. Copy its contents into the VM:

```bash
# On the VM, create the configuration file
cat > ~/.openclaw/openclaw.json << 'EOF'
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "azure-openai/gpt-5.2-codex",
        "fallbacks": ["azure-openai/gpt-5.2", "azure-openai/gpt-4o"]
      }
    }
  },
  ...
}
EOF
```

### 3. Start OpenClaw

```bash
# Option A: With the onboarding wizard
openclaw onboard --install-daemon

# Option B: Manual start
./start.sh

# Check the status
./status.sh
```

### 4. Access the Dashboard

The OpenClaw dashboard is accessible at `http://localhost:18789/` from the VM.

To access it from your local machine, use a tunnel via Bastion (requires Bastion Standard):

```bash
az network bastion tunnel \
  --name bastion-openclaw \
  --resource-group rg-openclaw \
  --target-resource-id <VM_RESOURCE_ID> \
  --resource-port 18789 \
  --port 8080
```

Then open `http://localhost:8080` in your browser.

## 🤖 Multi-Model Support

OpenClaw is configured with multiple fallback models:

| Model | Alias | Usage |
|-------|-------|-------|
| `gpt-5.2-codex` | Codex 5.2 | Primary - advanced coding |
| `gpt-5.2` | GPT-5.2 | Fallback - general purpose |
| `gpt-4o` | GPT-4o | Fallback - fast |

To switch models during a conversation:

```
/model
/model 2
/model azure-openai/gpt-5.2
```

## 🔍 Web Search

OpenClaw supports **Brave Search** and **Perplexity** by default. To use Bing Search, you will need to create a custom skill (see the skills documentation).

### Brave Search Configuration (recommended)

```bash
openclaw configure --section web
# Enter your Brave Search API key
```

### Alternative: Perplexity via OpenRouter

```json
{
  "tools": {
    "web": {
      "search": {
        "provider": "perplexity",
        "perplexity": {
          "apiKey": "sk-or-..."
        }
      }
    }
  }
}
```

## 🛠️ Custom Skills

To add skills to your agent:

```bash
# Create a skill folder
mkdir -p ~/.openclaw/workspace/skills/my-skill

# Create the SKILL.md file
cat > ~/.openclaw/workspace/skills/my-skill/SKILL.md << 'EOF'
# My Skill

Description of what the skill does...

## Instructions

Instructions for the agent...
EOF
```

Restart OpenClaw to load the skill.

## 💰 Estimated Costs

| Resource | SKU | Monthly Cost (estimated) |
|----------|-----|--------------------------|
| Azure VM | Standard_D2s_v5 | ~€35 |
| Azure Bastion | Basic | ~€27 |
| OS Disk | Premium SSD 128GB | ~€10 |
| Azure APIM | Consumption | ~€0 (pay-per-use) |
| Azure AI Foundry | Pay-as-you-go | Variable |
| **Total infra** | | **~€72/month** |

### Save Costs

```powershell
# Stop the VM when not in use
az vm deallocate -g rg-openclaw -n vm-openclaw

# Restart
az vm start -g rg-openclaw -n vm-openclaw
```

## 🔒 Security

- ✅ No public IP on the VM
- ✅ Access only via Azure Bastion
- ✅ AI Foundry with Entra ID authentication only
- ✅ APIM with Managed Identity
- ✅ API keys never exposed

## 🗑️ Cleanup

```powershell
az group delete -n rg-openclaw --yes --no-wait
```

## 📚 Resources

- [OpenClaw Documentation](https://docs.openclaw.ai/)
- [Getting Started](https://docs.openclaw.ai/start/getting-started)
- [Skills](https://docs.openclaw.ai/tools/skills)
- [Models](https://docs.openclaw.ai/concepts/models)
