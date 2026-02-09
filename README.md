# OpenClaw on Azure with AI Foundry

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FYOUR_USERNAME%2Fsample-OpenClaw-on-Azure-with-AI-Foundry%2Fmain%2Finfra%2Fmain.json)

Deploy [OpenClaw](https://github.com/openclaw/openclaw), a powerful open-source personal AI assistant, on Azure with Azure AI Foundry integration. This project provides a secure, enterprise-ready deployment pattern that allows you to safely test and run AI agents in the cloud.

## ⚠️ The Challenge: AI Foundry Authentication

**Azure AI Foundry does NOT provide API keys** - it only supports Entra ID (Azure AD) authentication with bearer tokens. This makes it challenging to use with tools like OpenClaw that expect a simple API key.

### Our Solution: Azure API Management (APIM) as Authentication Facade

We use APIM as a middleware that:
1. **Accepts a subscription key** from OpenClaw (via `Authorization: Bearer` header)
2. **Obtains a Managed Identity (MSI) token** for Azure Cognitive Services
3. **Forwards the request** to AI Foundry with the MSI bearer token

This way, OpenClaw can use a simple "API key" (APIM subscription key) while the actual authentication to AI Foundry is handled securely via Managed Identity.

## 🎯 Why This Project?

Running AI agents on your local machine can be risky - they can access your files, execute code, and interact with your system. This project provides a **safe sandbox environment** on Azure where you can:

- ✅ Run OpenClaw in an isolated Azure VM
- ✅ Use Azure AI Foundry for powerful AI capabilities (GPT-5.2, etc.)
- ✅ Connect securely via Azure Bastion (no public SSH/RDP)
- ✅ **Solve the Entra ID auth problem** with APIM + Managed Identity
- ✅ Monitor everything with Azure Monitor
- ✅ Control costs with auto-shutdown

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                 Azure                                        │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                    Virtual Network (10.0.0.0/16)                        │  │
│  │                                                                         │  │
│  │  ┌─────────────────┐     ┌──────────────────────────────────────────┐  │  │
│  │  │ Azure Bastion   │     │           Linux VM (OpenClaw)            │  │  │
│  │  │ (Secure Access) │────▶│  - Node.js 22 + npm                      │  │  │
│  │  └─────────────────┘     │  - OpenClaw (native install)             │  │  │
│  │                          │  - Gateway + TUI                          │  │  │
│  │                          └──────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                       │                                       │
│                                       │ HTTPS                                 │
│                                       ▼                                       │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                 Azure API Management (APIM)                             │  │
│  │                                                                         │  │
│  │   1. Reçoit: Authorization: Bearer <subscription-key>                   │  │
│  │   2. Obtient: MSI Token pour cognitiveservices.azure.com                │  │
│  │   3. Forward: Authorization: Bearer <msi-token>                         │  │
│  │                                                                         │  │
│  │   🔐 Managed Identity: "Cognitive Services OpenAI User"                 │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                       │                                       │
│                                       │ HTTPS (MSI Auth)                      │
│                                       ▼                                       │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                        Azure AI Foundry                                 │  │
│  │                                                                         │  │
│  │   Deployments:                                                          │  │
│  │   - gpt-5.2 (chat completions)                                          │  │
│  │   - gpt-5.2-codex (code completion - pas de chat)                       │  │
│  │                                                                         │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 🔧 Configuration OpenClaw (CRITIQUE)

La configuration d'OpenClaw pour fonctionner avec Azure AI Foundry via APIM est spécifique. Voici la configuration exacte qui fonctionne :

### Fichier `~/.openclaw/openclaw.json`

```json
{
  "gateway": {
    "mode": "local",
    "auth": {
      "token": "YOUR_GATEWAY_TOKEN"
    }
  },
  "agents": {
    "defaults": {
      "workspace": "~/.openclaw/workspace",
      "model": {
        "primary": "azure-apim/gpt-5.2"
      }
    }
  },
  "models": {
    "mode": "merge",
    "providers": {
      "azure-apim": {
        "baseUrl": "https://YOUR_APIM_NAME.azure-api.net/openai/deployments/gpt-5.2",
        "apiKey": "YOUR_APIM_SUBSCRIPTION_KEY",
        "api": "openai-completions",
        "models": [
          {
            "id": "gpt-5.2",
            "name": "GPT 5.2 via APIM",
            "reasoning": false,
            "input": ["text"],
            "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
            "contextWindow": 128000,
            "maxTokens": 32000
          }
        ]
      }
    }
  }
}
```

### Points clés de la configuration :

| Paramètre | Valeur | Explication |
|-----------|--------|-------------|
| `api` | `"openai-completions"` | **OBLIGATOIRE** - Type d'API OpenAI |
| `baseUrl` | `https://<apim>/openai/deployments/<model>` | Inclut le chemin du deployment |
| `apiKey` | Subscription key APIM | Pas la clé AI Foundry (qui n'existe pas) |

### ⚠️ Erreurs courantes à éviter :

1. **`api: undefined`** → Le champ `api` est obligatoire, utilisez `"openai-completions"`
2. **`api: "azure-openai"`** → Valeur invalide, utilisez `"openai-completions"`
3. **`api: "openai"`** → Valeur invalide pour les providers custom
4. **Context window trop petit** → Minimum 16000 tokens requis par OpenClaw

## 🔐 Configuration APIM (Policy)

La policy APIM doit :
1. Accepter `Authorization: Bearer <subscription-key>` (car OpenClaw utilise ce format)
2. Obtenir un token MSI pour Azure Cognitive Services
3. Remplacer le header Authorization par le token MSI

### Policy XML pour l'opération `chat-completions` :

```xml
<policies>
    <inbound>
        <base />
        <!-- Extraire le token Bearer et le mettre dans api-key si pas déjà présent -->
        <choose>
            <when condition="@(!context.Request.Headers.ContainsKey(&quot;api-key&quot;) 
                             &amp;&amp; context.Request.Headers.ContainsKey(&quot;Authorization&quot;))">
                <set-header name="api-key" exists-action="override">
                    <value>@{
                        var authHeader = context.Request.Headers.GetValueOrDefault("Authorization", "");
                        if (authHeader.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase)) {
                            return authHeader.Substring(7);
                        }
                        return authHeader;
                    }</value>
                </set-header>
            </when>
        </choose>
        <!-- Obtenir le token MSI pour AI Foundry -->
        <authentication-managed-identity 
            resource="https://cognitiveservices.azure.com" 
            output-token-variable-name="msi-access-token" 
            ignore-error="false" />
        <!-- Remplacer Authorization par le token MSI -->
        <set-header name="Authorization" exists-action="override">
            <value>@("Bearer " + (string)context.Variables["msi-access-token"])</value>
        </set-header>
        <!-- Rediriger vers AI Foundry -->
        <set-backend-service base-url="https://YOUR_AI_FOUNDRY.openai.azure.com/openai" />
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
```

### Configuration API APIM :

L'API doit être configurée avec `subscriptionRequired: false` pour que la policy puisse gérer l'authentification :

```json
{
  "properties": {
    "subscriptionRequired": false,
    "subscriptionKeyParameterNames": {
      "header": "api-key",
      "query": "subscription-key"
    }
  }
}
```

## 🚀 Démarrage rapide (avec infra existante)

Si vous avez déjà un AI Foundry déployé, voici les étapes pour configurer OpenClaw :

### 1. Déployer APIM + VM + Bastion

```bash
# Via PowerShell
./scripts/deploy-simple.ps1 -ResourceGroupName "rg-openclaw" -AiFoundryEndpoint "https://your-foundry.openai.azure.com"
```

### 2. Se connecter à la VM via Bastion

Allez dans le portail Azure → VM → Connect → Bastion

### 3. Installer OpenClaw sur la VM

```bash
# Installer Node.js 22
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs

# Installer OpenClaw
sudo npm install -g openclaw

# Configuration initiale
openclaw setup
```

### 4. Configurer OpenClaw

```bash
cat > ~/.openclaw/openclaw.json << 'EOF'
{
  "gateway": {
    "mode": "local",
    "auth": {
      "token": "your-secure-token"
    }
  },
  "agents": {
    "defaults": {
      "workspace": "~/.openclaw/workspace",
      "model": {
        "primary": "azure-apim/gpt-5.2"
      }
    }
  },
  "models": {
    "mode": "merge",
    "providers": {
      "azure-apim": {
        "baseUrl": "https://YOUR_APIM.azure-api.net/openai/deployments/gpt-5.2",
        "apiKey": "YOUR_APIM_SUBSCRIPTION_KEY",
        "api": "openai-completions",
        "models": [
          {
            "id": "gpt-5.2",
            "name": "GPT 5.2 via APIM",
            "reasoning": false,
            "input": ["text"],
            "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
            "contextWindow": 128000,
            "maxTokens": 32000
          }
        ]
      }
    }
  }
}
EOF
```

### 5. Démarrer OpenClaw

```bash
# Terminal 1: Démarrer le gateway
OPENCLAW_GATEWAY_TOKEN="your-secure-token" openclaw gateway --verbose &

# Terminal 2: Démarrer le TUI
OPENCLAW_GATEWAY_TOKEN="your-secure-token" openclaw
```

## ⚡ Quick Start - One Command Deployment

- Azure subscription with Contributor access
- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) installed
- That's it! Everything else is automated 🎉

### Deploy in One Command

**🚀 Fully Automated - Zero Manual Steps!**

This single command deploys everything: VM, AI Foundry, model, Bastion, and starts OpenClaw automatically.

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/sample-OpenClaw-on-Azure-with-AI-Foundry.git
cd sample-OpenClaw-on-Azure-with-AI-Foundry

# Deploy everything with ONE command (PowerShell)
./scripts/deploy-complete.ps1 -ResourceGroupName "rg-openclaw-sandbox"

# OR on Linux/macOS (Bash)
./scripts/deploy-complete.sh --resource-group "rg-openclaw-sandbox"
```

**What gets deployed automatically:**
- ✅ Azure VM with Node.js and OpenClaw installed
- ✅ Azure AI Foundry with GPT-5 model deployed
- ✅ Azure Bastion for secure access (no public IP)
- ✅ Managed Identity with role assignments
- ✅ OpenClaw configured and running!

**Deployment time:** ~10-15 minutes

### Connect to Your VM

After deployment completes, the script displays your credentials.

1. Go to Azure Portal → Resource Groups → Your RG → Your VM
2. Click **Connect** → **Bastion**
3. Enter the credentials shown by the deployment script
4. OpenClaw is already running! 🎉

### Verify OpenClaw is Running

```bash
# Check status (OpenClaw should already be running!)
./status.sh

# If needed, restart OpenClaw
./start.sh

# View logs
journalctl -u openclaw -f
```

##  Cost Estimate

| Resource | SKU | Monthly Cost (Est.) |
|----------|-----|---------------------|
| Azure VM | Standard_D2s_v5 | ~$35 |
| Azure Bastion | Basic | ~$27 |
| OS Disk | Premium SSD 128GB | ~$10 |
| Azure AI Foundry | Pay-as-you-go | Variable |
| **Total Infrastructure** | | **~$72/month** |

💡 **Cost Saving Tips:**
- Use Azure Bastion Developer SKU (free, but limited)
- Enable auto-shutdown for non-production hours
- Use Spot VMs for test environments
- Delete Bastion when not needed

## 🔒 Security Features

- **No Public IP**: VM has no public IP address
- **Azure Bastion**: Secure browser-based access without exposing RDP/SSH
- **Managed Identity**: Keyless authentication to Azure AI Foundry
- **Network Security Group**: Restrictive firewall rules
- **Encryption**: Disk encryption enabled by default
- **RBAC**: Fine-grained access control

## 📁 Project Structure

```
sample-OpenClaw-on-Azure-with-AI-Foundry/
├── README.md                       # This file
├── configs/
│   └── openclaw-azure-apim.json   # ⭐ Template de config OpenClaw
├── infra/
│   ├── main-complete.bicep        # Complete infrastructure (recommended)
│   ├── main.bicep                 # Basic infrastructure template
│   ├── main.bicepparam            # Parameters file
│   └── cloud-init.yaml            # VM initialization script
├── scripts/
│   ├── deploy-with-apim.ps1       # ⭐ Déploiement complet avec APIM (recommandé)
│   ├── deploy-complete.ps1        # One-click deployment (PowerShell)
│   ├── deploy-complete.sh         # One-click deployment (Bash)
│   ├── deploy.ps1                 # Basic deployment script
│   └── deploy.sh                  # Basic deployment script
├── docs/
│   ├── DEPLOYMENT.md              # Detailed deployment guide
│   ├── USAGE.md                   # Configuration and usage guide
│   ├── SECURITY.md                # Security considerations
│   └── TROUBLESHOOTING.md         # Common issues and solutions
└── .github/
    └── workflows/
        └── deploy.yml             # GitHub Actions workflow
```

## 🔧 Troubleshooting OpenClaw + Azure

### Erreur: "No API provider registered for api: undefined"

**Cause**: Le champ `api` manque ou a une valeur invalide dans la config OpenClaw.

**Solution**: Ajoutez `"api": "openai-completions"` dans votre provider :
```json
{
  "models": {
    "providers": {
      "azure-apim": {
        "api": "openai-completions",  // ← OBLIGATOIRE
        ...
      }
    }
  }
}
```

### Erreur: "Model context window too small"

**Cause**: OpenClaw requiert un minimum de 16000 tokens de context window.

**Solution**: Mettez `"contextWindow": 32000` ou plus dans votre modèle.

### Erreur: "401 Access denied due to missing subscription key"

**Cause**: APIM ne reconnaît pas le header d'authentification.

**Solution**: 
1. Configurez `subscriptionRequired: false` sur l'API APIM
2. Assurez-vous que la policy extrait le token du header `Authorization: Bearer`

### L'agent démarre mais "(no output)"

**Cause**: L'agent ne fait pas d'appel HTTP vers l'API.

**Vérification**:
```bash
# Voir les logs détaillés
OPENCLAW_LOG_LEVEL=trace openclaw gateway --verbose 2>&1 | tee /tmp/trace.log

# Chercher les erreurs
grep -iE "error|http|fetch" /tmp/trace.log
```

### Tester l'API directement

```bash
# Test avec api-key header
curl -X POST "https://YOUR_APIM.azure-api.net/openai/deployments/gpt-5.2/chat/completions?api-version=2024-10-21" \
  -H "Content-Type: application/json" \
  -H "api-key: YOUR_SUBSCRIPTION_KEY" \
  -d '{"messages":[{"role":"user","content":"Hello"}]}'

# Test avec Authorization: Bearer (comme OpenClaw)
curl -X POST "https://YOUR_APIM.azure-api.net/openai/deployments/gpt-5.2/chat/completions?api-version=2024-10-21" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_SUBSCRIPTION_KEY" \
  -d '{"messages":[{"role":"user","content":"Hello"}]}'
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [OpenClaw](https://github.com/openclaw/openclaw) - The amazing open-source personal AI assistant
- Azure Verified Modules team for the excellent Bicep modules

## 📫 Support

- **Issues**: Please open a GitHub issue for bug reports or feature requests
- **Discussions**: Use GitHub Discussions for questions and community support

---

Made with ❤️ for the Azure and AI community
