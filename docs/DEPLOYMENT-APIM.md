# OpenClaw on Azure avec APIM - Guide de déploiement

Ce guide explique comment déployer OpenClaw sur Azure avec Azure API Management pour résoudre le problème d'authentification Entra ID.

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
│                                    │ HTTPS (clé API APIM)                │
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

## 🚀 Déploiement rapide

### Prérequis

- Abonnement Azure avec accès à GPT-5.2-codex
- Azure CLI installé
- PowerShell 7+

### Déployer

```powershell
# Cloner le repository
cd sample-OpenClaw-on-Azure-with-AI-Foundry

# Déployer (15-20 minutes)
./scripts/deploy-apim.ps1 -ResourceGroup "rg-openclaw"
```

### Paramètres optionnels

| Paramètre | Défaut | Description |
|-----------|--------|-------------|
| `-ResourceGroup` | `rg-openclaw` | Nom du Resource Group |
| `-Location` | `swedencentral` | Région Azure |
| `-ModelName` | `gpt-5.2-codex` | Modèle à déployer |
| `-ModelVersion` | `2026-01-01` | Version du modèle |
| `-PublisherEmail` | `admin@contoso.com` | Email pour APIM |

## 📋 Après le déploiement

### 1. Se connecter à la VM via Bastion

1. Allez sur [portal.azure.com](https://portal.azure.com)
2. Resource Groups → votre RG → votre VM
3. Cliquez **Connect** → **Bastion**
4. Entrez les credentials affichés par le script

### 2. Configurer OpenClaw

Le script de déploiement génère un fichier `openclaw-config-*.json`. Copiez son contenu dans la VM :

```bash
# Sur la VM, créer le fichier de configuration
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

### 3. Lancer OpenClaw

```bash
# Option A: Avec le wizard d'onboarding
openclaw onboard --install-daemon

# Option B: Démarrage manuel
./start.sh

# Vérifier le statut
./status.sh
```

### 4. Accéder au Dashboard

Le dashboard OpenClaw est accessible sur `http://localhost:18789/` depuis la VM.

Pour y accéder depuis votre machine locale, utilisez un tunnel via Bastion (nécessite Bastion Standard) :

```bash
az network bastion tunnel \
  --name bastion-openclaw \
  --resource-group rg-openclaw \
  --target-resource-id <VM_RESOURCE_ID> \
  --resource-port 18789 \
  --port 8080
```

Puis ouvrez `http://localhost:8080` dans votre navigateur.

## 🤖 Multi-modèles

OpenClaw est configuré avec plusieurs modèles en fallback :

| Modèle | Alias | Utilisation |
|--------|-------|-------------|
| `gpt-5.2-codex` | Codex 5.2 | Principal - codage avancé |
| `gpt-5.2` | GPT-5.2 | Fallback - général |
| `gpt-4o` | GPT-4o | Fallback - rapide |

Pour changer de modèle en cours de conversation :

```
/model
/model 2
/model azure-openai/gpt-5.2
```

## 🔍 Recherche Web

OpenClaw supporte par défaut **Brave Search** et **Perplexity**. Pour utiliser Bing Search, vous devrez créer un skill personnalisé (voir documentation des skills).

### Configuration Brave Search (recommandé)

```bash
openclaw configure --section web
# Entrez votre clé API Brave Search
```

### Alternative : Perplexity via OpenRouter

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

## 🛠️ Skills personnalisés

Pour ajouter des skills à votre agent :

```bash
# Créer un dossier de skill
mkdir -p ~/.openclaw/workspace/skills/mon-skill

# Créer le fichier SKILL.md
cat > ~/.openclaw/workspace/skills/mon-skill/SKILL.md << 'EOF'
# Mon Skill

Description de ce que fait le skill...

## Instructions

Instructions pour l'agent...
EOF
```

Redémarrez OpenClaw pour charger le skill.

## 💰 Coûts estimés

| Ressource | SKU | Coût mensuel (estimé) |
|-----------|-----|----------------------|
| Azure VM | Standard_D2s_v5 | ~35€ |
| Azure Bastion | Basic | ~27€ |
| OS Disk | Premium SSD 128GB | ~10€ |
| Azure APIM | Consumption | ~0€ (pay-per-use) |
| Azure AI Foundry | Pay-as-you-go | Variable |
| **Total infra** | | **~72€/mois** |

### Économiser

```powershell
# Arrêter la VM quand non utilisée
az vm deallocate -g rg-openclaw -n vm-openclaw

# Redémarrer
az vm start -g rg-openclaw -n vm-openclaw
```

## 🔒 Sécurité

- ✅ Pas d'IP publique sur la VM
- ✅ Accès uniquement via Azure Bastion
- ✅ AI Foundry avec authentification Entra ID uniquement
- ✅ APIM avec Managed Identity
- ✅ Clés API jamais exposées

## 🗑️ Nettoyage

```powershell
az group delete -n rg-openclaw --yes --no-wait
```

## 📚 Ressources

- [Documentation OpenClaw](https://docs.openclaw.ai/)
- [Getting Started](https://docs.openclaw.ai/start/getting-started)
- [Skills](https://docs.openclaw.ai/tools/skills)
- [Models](https://docs.openclaw.ai/concepts/models)
