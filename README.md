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

```mermaid
graph TD
    subgraph Azure["☁️ Azure"]
        subgraph VNet["Virtual Network 10.0.0.0/16"]
            Bastion["🔒 Azure Bastion<br/><i>Secure browser access</i>"]
            VM["🖥️ Linux VM<br/><b>OpenClaw</b><br/>Node.js 22 · Gateway · TUI"]
            Bastion -->|"SSH via browser"| VM
        end

        subgraph Storage["Azure Storage"]
            Blob["📦 Blob Storage<br/><i>stopenclawmedia / media</i>"]
        end

        APIM["🔐 Azure API Management<br/><br/>1. Receives: Bearer subscription-key<br/>2. Gets: MSI Token<br/>3. Forwards: Bearer msi-token<br/><br/><i>Managed Identity: Cognitive Services OpenAI User</i>"]

        AIFoundry["🧠 Azure AI Foundry<br/><br/>• gpt-5.2 — chat completions<br/>• gpt-5.2-codex — code completion<br/>• gpt-4o-transcribe — audio<br/>• Azure Speech — TTS"]
    end

    Telegram["📱 Telegram<br/><i>Users send messages</i>"]
    User["👤 Admin<br/><i>Azure Bastion</i>"]

    User -->|"Bastion"| Bastion
    Telegram -->|"Bot API"| VM
    VM -->|"HTTPS · subscription-key"| APIM
    VM -->|"Managed Identity · Azure SDK"| Blob
    APIM -->|"HTTPS · MSI bearer token"| AIFoundry

    style Azure fill:#e8f4fd,stroke:#0078d4,stroke-width:2px
    style VNet fill:#d4edda,stroke:#28a745,stroke-width:1px
    style Storage fill:#fff3cd,stroke:#ffc107,stroke-width:1px
    style APIM fill:#f8d7da,stroke:#dc3545,stroke-width:1px
    style AIFoundry fill:#e2d5f1,stroke:#6f42c1,stroke-width:1px
    style VM fill:#d4edda,stroke:#28a745,stroke-width:2px
    style Telegram fill:#e3f2fd,stroke:#0088cc,stroke-width:1px
    style Blob fill:#fff3cd,stroke:#ffc107,stroke-width:1px
```

## 🔧 OpenClaw Configuration (CRITICAL)

The OpenClaw configuration to work with Azure AI Foundry via APIM requires specific settings. Here is the exact working configuration:

### File `~/.openclaw/openclaw.json`

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

### Key Configuration Notes:

| Parameter | Value | Explanation |
|-----------|-------|-------------|
| `api` | `"openai-completions"` | **REQUIRED** - OpenAI API type |
| `baseUrl` | `https://<apim>/openai/deployments/<model>` | Includes the deployment path |
| `apiKey` | APIM subscription key | Not an AI Foundry key (which doesn't exist) |

### ⚠️ Common Mistakes to Avoid:

1. **`api: undefined`** → The `api` field is required, use `"openai-completions"`
2. **`api: "azure-openai"`** → Invalid value, use `"openai-completions"`
3. **`api: "openai"`** → Invalid value for custom providers
4. **Context window too small** → Minimum 16000 tokens required by OpenClaw

## 🔐 APIM Configuration (Policy)

The APIM policy must:
1. Accept `Authorization: Bearer <subscription-key>` (since OpenClaw uses this format)
2. Obtain an MSI token for Azure Cognitive Services
3. Replace the Authorization header with the MSI token

### XML Policy for the `chat-completions` operation:

```xml
<policies>
    <inbound>
        <base />
        <!-- Extract Bearer token and set it as api-key if not already present -->
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
        <!-- Get MSI token for AI Foundry -->
        <authentication-managed-identity 
            resource="https://cognitiveservices.azure.com" 
            output-token-variable-name="msi-access-token" 
            ignore-error="false" />
        <!-- Replace Authorization with MSI token -->
        <set-header name="Authorization" exists-action="override">
            <value>@("Bearer " + (string)context.Variables["msi-access-token"])</value>
        </set-header>
        <!-- Redirect to AI Foundry -->
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

### APIM API Configuration:

The API must be configured with `subscriptionRequired: false` so the policy can handle authentication:

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

## 🚀 Quick Start (with existing infrastructure)

If you already have AI Foundry deployed, here are the steps to configure OpenClaw:

### 1. Deploy APIM + VM + Bastion

```bash
# Via PowerShell
./scripts/deploy-simple.ps1 -ResourceGroupName "rg-openclaw" -AiFoundryEndpoint "https://your-foundry.openai.azure.com"
```

### 2. Connect to the VM via Bastion

Go to Azure Portal → VM → Connect → Bastion

### 3. Install OpenClaw on the VM

```bash
# Install Node.js 22
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs

# Install OpenClaw
sudo npm install -g openclaw

# Initial setup
openclaw setup
```

### 4. Configure OpenClaw

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

### 5. Start OpenClaw

```bash
# Terminal 1: Start the gateway
OPENCLAW_GATEWAY_TOKEN="your-secure-token" openclaw gateway --verbose &

# Terminal 2: Start the TUI
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

## 👥 Multi-Agent: Dedicated Agent per Telegram User

OpenClaw supports **multi-agent**: each Telegram user can be routed to a specific agent with its own workspace, skills, and restrictions.

### Use Case: Corinne

Corinne is a non-technical user. She should only have access to **a single feature**: send a YouTube link and receive the video dubbed in French. No shell, no code, no browsing — just Telegram.

To achieve this, a dedicated `corinne` agent is configured:

1. **Separate agent** with an isolated workspace (`~/.openclaw/workspace-corinne/`)
2. **Telegram binding**: Corinne's DMs are automatically routed to the `corinne` agent
3. **Restrictive SOUL.md**: the agent does only one thing (dub YouTube videos)
4. **Restricted skills**: only skills from Corinne's workspace are accessible

```json
// In ~/.openclaw/openclaw.json
{
  "agents": {
    "list": [
      { "id": "main", "default": true },
      {
        "id": "corinne",
        "name": "Corinne",
        "workspace": "/home/azureuser/.openclaw/workspace-corinne"
      }
    ]
  },
  "bindings": [
    {
      "agentId": "corinne",
      "match": {
        "channel": "telegram",
        "peer": { "kind": "dm", "id": "TELEGRAM_USER_ID" }
      }
    }
  ]
}
```

For more details, see [docs/USAGE.md](docs/USAGE.md#multi-agent-dedicated-agent-per-user).

## 📁 Project Structure

```
sample-OpenClaw-on-Azure-with-AI-Foundry/
├── README.md                       # This file
├── configs/
│   └── openclaw-azure-apim.json   # ⭐ OpenClaw config template
├── skills/
│   ├── yt_fr_dub/                 # 🎬 YouTube French dubbing skill
│   │   ├── run.js                 # Main script (Azure SDK + Managed Identity)
│   │   ├── SKILL.md               # Skill definition for OpenClaw
│   │   └── package.json           # Dependencies (@azure/identity, @azure/storage-blob)
│   └── yt-dlp-downloader-skill/   # 📥 Video downloader skill
│       └── SKILL.md               # Skill definition
├── infra/
│   ├── main-complete.bicep        # Complete infrastructure (recommended)
│   ├── main.bicep                 # Basic infrastructure template
│   ├── main.bicepparam            # Parameters file
│   └── cloud-init.yaml            # VM initialization script
├── scripts/
│   ├── deploy-with-apim.ps1       # ⭐ Full deployment with APIM (recommended)
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

### Error: "No API provider registered for api: undefined"

**Cause**: The `api` field is missing or has an invalid value in the OpenClaw config.

**Solution**: Add `"api": "openai-completions"` to your provider:
```json
{
  "models": {
    "providers": {
      "azure-apim": {
        "api": "openai-completions",  // ← REQUIRED
        ...
      }
    }
  }
}
```

### Error: "Model context window too small"

**Cause**: OpenClaw requires a minimum of 16000 tokens for the context window.

**Solution**: Set `"contextWindow": 32000` or higher in your model.

### Error: "401 Access denied due to missing subscription key"

**Cause**: APIM does not recognize the authentication header.

**Solution**: 
1. Set `subscriptionRequired: false` on the APIM API
2. Make sure the policy extracts the token from the `Authorization: Bearer` header

### Agent starts but "(no output)"

**Cause**: The agent is not making HTTP calls to the API.

**Verification**:
```bash
# View detailed logs
OPENCLAW_LOG_LEVEL=trace openclaw gateway --verbose 2>&1 | tee /tmp/trace.log

# Search for errors
grep -iE "error|http|fetch" /tmp/trace.log
```

### Test the API Directly

```bash
# Test with api-key header
curl -X POST "https://YOUR_APIM.azure-api.net/openai/deployments/gpt-5.2/chat/completions?api-version=2024-10-21" \
  -H "Content-Type: application/json" \
  -H "api-key: YOUR_SUBSCRIPTION_KEY" \
  -d '{"messages":[{"role":"user","content":"Hello"}]}'

# Test with Authorization: Bearer (as OpenClaw uses)
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
