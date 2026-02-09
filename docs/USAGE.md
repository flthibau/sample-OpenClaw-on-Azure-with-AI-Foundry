# Configuration and Usage Guide

This guide provides detailed instructions for configuring and using OpenClaw on your Azure deployment.

## Table of Contents

- [First Connection](#first-connection)
- [Azure AI Foundry Configuration](#azure-ai-foundry-configuration)
- [OpenClaw Configuration](#openclaw-configuration)
- [Starting OpenClaw](#starting-openclaw)
- [Connecting Messaging Channels](#connecting-messaging-channels)
- [Using OpenClaw](#using-openclaw)
- [Multi-Agent: Dedicated Agent per User](#multi-agent-dedicated-agent-per-user)
- [Advanced Configuration](#advanced-configuration)
- [Monitoring and Logs](#monitoring-and-logs)
- [Updating OpenClaw](#updating-openclaw)

---

## First Connection

### Connect via Azure Bastion

1. Go to [Azure Portal](https://portal.azure.com)
2. Navigate to **Resource Groups** → Select your resource group (e.g., `rg-openclaw-dev`)
3. Click on your **Virtual Machine** (e.g., `vm-openclaw-dev`)
4. Click **Connect** → **Bastion**
5. Enter your credentials:
   - **Username**: `azureuser` (or your custom username)
   - **Password**: The password you set during deployment
6. Click **Connect**

A new browser tab opens with a terminal session to your VM.

### Welcome Screen

When you first connect, you'll see a custom welcome message:

```
╔═══════════════════════════════════════════════════════════════╗
║                  🤖 OpenClaw on Azure 🤖                       ║
║                                                               ║
║  Your AI assistant is ready to be configured!                ║
║                                                               ║
║  Quick commands:                                              ║
║    ./start.sh          - Start OpenClaw                      ║
║    ./setup-azure-ai.sh - Test Azure AI Foundry connection    ║
║    cd ~/openclaw       - Go to OpenClaw directory            ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
```

---

## Azure AI Foundry Configuration

### Prerequisites

Before configuring OpenClaw, you need:

1. An **Azure AI Foundry** resource (Azure OpenAI)
2. A **model deployment** (e.g., GPT-5)
3. The **endpoint URL** of your AI Foundry resource

### Step 1: Create Azure AI Foundry Resource (if needed)

If you don't have an Azure AI Foundry resource:

```bash
# Create AI Foundry resource
az cognitiveservices account create \
  --name "ai-foundry-openclaw" \
  --resource-group "rg-openclaw-dev" \
  --kind "OpenAI" \
  --sku "S0" \
  --location "eastus2" \
  --custom-domain "ai-foundry-openclaw"
```

### Step 2: Deploy a Model

In the Azure Portal:

1. Go to **Azure AI Foundry** → Your resource
2. Click **Model Deployments** → **Create**
3. Select a model (e.g., `gpt-5`)
4. Set deployment name (e.g., `gpt-5-deployment`)
5. Configure tokens per minute quota
6. Click **Create**

Or via CLI:

```bash
az cognitiveservices account deployment create \
  --name "ai-foundry-openclaw" \
  --resource-group "rg-openclaw-dev" \
  --deployment-name "gpt-5-deployment" \
  --model-name "gpt-5" \
  --model-version "2026-01-01" \
  --model-format "OpenAI" \
  --sku-capacity 10 \
  --sku-name "Standard"
```

### Step 3: Grant Managed Identity Access

The VM uses a Managed Identity for secure authentication. Grant it access to AI Foundry:

```bash
# Get VM's Managed Identity Principal ID
PRINCIPAL_ID=$(az vm identity show \
  --resource-group rg-openclaw-dev \
  --name vm-openclaw-dev \
  --query principalId -o tsv)

# Get AI Foundry resource ID
AI_FOUNDRY_ID=$(az cognitiveservices account show \
  --name ai-foundry-openclaw \
  --resource-group rg-openclaw-dev \
  --query id -o tsv)

# Grant Cognitive Services OpenAI User role
az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "Cognitive Services OpenAI User" \
  --scope $AI_FOUNDRY_ID
```

### Step 4: Test the Connection

On the VM, run:

```bash
./setup-azure-ai.sh
```

Expected output:

```
🔍 Testing Azure Managed Identity...
✅ Successfully obtained token!

🔍 Testing Azure AI Foundry connection...
✅ Connection successful!

Your VM is ready to use Azure AI Foundry with Managed Identity.
```

---

## OpenClaw Configuration

### Configuration File

OpenClaw uses a `.env` file for configuration. Create it from the template:

```bash
cd ~/openclaw
cp .env.example .env
nano .env
```

### Essential Settings

```env
# ===========================================
# Azure AI Foundry Configuration
# ===========================================

# Use Managed Identity (recommended)
AZURE_USE_MANAGED_IDENTITY=true

# AI Foundry Endpoint
AZURE_OPENAI_ENDPOINT=https://ai-foundry-openclaw.openai.azure.com/

# Model Deployment Name
AZURE_OPENAI_DEPLOYMENT=gpt-5-deployment

# API Version (use latest)
AZURE_OPENAI_API_VERSION=2024-10-01-preview

# ===========================================
# OpenClaw General Settings
# ===========================================

# Application Name
APP_NAME=OpenClaw

# Log Level (debug, info, warn, error)
LOG_LEVEL=info

# Server Port
PORT=18789

# ===========================================
# Security Settings
# ===========================================

# Session Secret (generate a random string)
SESSION_SECRET=your-random-secret-here-change-me

# Enable HTTPS (recommended for production)
HTTPS_ENABLED=false

# Allowed Origins (CORS)
ALLOWED_ORIGINS=http://localhost:3000
```

### Generate Session Secret

```bash
# Generate a secure random secret
openssl rand -hex 32
```

Copy the output and paste it as your `SESSION_SECRET`.

---

## Starting OpenClaw

### Quick Start

Use the provided helper script:

```bash
./start.sh
```

This will:
1. Check prerequisites (configuration)
2. Start all services
3. Show the access URL

### Manual Start

```bash
# Start OpenClaw service
sudo systemctl start openclaw

# View logs
journalctl -u openclaw -f

# Stop
sudo systemctl stop openclaw
```

### Verify OpenClaw is Running

```bash
# Check service status
systemctl status openclaw

# Expected output:
# ● openclaw.service - OpenClaw Gateway Service
#      Active: active (running)
```

### Access the Web Interface

OpenClaw runs on port 18789. Since the VM has no public IP, you have two options:

#### Option A: SSH Tunnel via Bastion

1. In Azure Portal, use Bastion's **native client** feature (requires Bastion Standard SKU)
2. Or use Azure CLI:

```bash
# From your local machine
az network bastion tunnel \
  --name bastion-openclaw-dev \
  --resource-group rg-openclaw-dev \
  --target-resource-id <VM_RESOURCE_ID> \
  --resource-port 18789 \
  --port 8080
```

Then open `http://localhost:8080` in your browser.

#### Option B: Use Messaging Channels

Configure a messaging channel (Telegram, Slack, etc.) to interact with OpenClaw without needing direct web access.

---

## Connecting Messaging Channels

OpenClaw supports multiple messaging channels. Configure one or more:

### Telegram

1. Create a bot via [@BotFather](https://t.me/botfather):
   - Send `/newbot`
   - Follow instructions to get your bot token

2. Add to `.env`:

```env
# Telegram Configuration
TELEGRAM_ENABLED=true
TELEGRAM_BOT_TOKEN=123456789:ABCdefGHIjklMNOpqrsTUVwxyz
```

3. Restart OpenClaw:

```bash
sudo systemctl restart openclaw
```

4. Start a chat with your bot on Telegram!

### Slack

1. Create a Slack App at [api.slack.com/apps](https://api.slack.com/apps)

2. Configure OAuth & Permissions:
   - Bot Token Scopes: `app_mentions:read`, `chat:write`, `im:history`, `im:read`, `im:write`

3. Install to your workspace and get the Bot Token

4. Add to `.env`:

```env
# Slack Configuration
SLACK_ENABLED=true
SLACK_BOT_TOKEN=xoxb-your-bot-token
SLACK_SIGNING_SECRET=your-signing-secret
SLACK_APP_TOKEN=xapp-your-app-token
```

### Discord

1. Create a bot at [discord.com/developers](https://discord.com/developers/applications)

2. Get your bot token from Bot settings

3. Add to `.env`:

```env
# Discord Configuration
DISCORD_ENABLED=true
DISCORD_BOT_TOKEN=your-discord-bot-token
```

### Microsoft Teams

1. Register an app in Azure AD
2. Create a Bot Channel Registration
3. Add to `.env`:

```env
# Teams Configuration
TEAMS_ENABLED=true
TEAMS_APP_ID=your-app-id
TEAMS_APP_PASSWORD=your-app-password
```

### WhatsApp (via Twilio)

1. Set up Twilio WhatsApp Sandbox or Business API
2. Add to `.env`:

```env
# WhatsApp Configuration (Twilio)
WHATSAPP_ENABLED=true
TWILIO_ACCOUNT_SID=your-account-sid
TWILIO_AUTH_TOKEN=your-auth-token
TWILIO_WHATSAPP_NUMBER=+14155238886
```

---

## Using OpenClaw

### Basic Interactions

Once configured, you can chat with OpenClaw through your chosen channel:

```
You: Hello! What can you do?

OpenClaw: Hello! I'm OpenClaw, your personal AI assistant. I can help you with:
- Answering questions on various topics
- Writing and editing text
- Coding assistance
- Research and analysis
- Task automation
- And much more!

How can I assist you today?
```

### Agent Capabilities

OpenClaw is an AI agent, meaning it can:

1. **Execute Actions**: Run commands, search the web, manage files
2. **Use Tools**: Calculator, code execution, API calls
3. **Memory**: Remember context within a conversation
4. **Multi-step Tasks**: Break down complex tasks into steps

### Example Use Cases

#### Code Review

```
You: Review this Python function:
def factorial(n):
    if n == 0: return 1
    return n * factorial(n-1)

OpenClaw: Here's my review of your factorial function:

✅ Correct Implementation: The recursive logic is correct.

⚠️ Suggestions:
1. Add input validation for negative numbers
2. Consider iterative approach for large n (avoid stack overflow)
3. Add type hints for clarity

Improved version:
def factorial(n: int) -> int:
    if n < 0:
        raise ValueError("n must be non-negative")
    if n == 0:
        return 1
    return n * factorial(n - 1)
```

#### Research

```
You: What are the latest trends in cloud-native security for 2026?

OpenClaw: Based on current trends in cloud-native security for 2026:

1. **Zero Trust Architecture**: Now standard, not optional
2. **AI-Powered Threat Detection**: Real-time anomaly detection
3. **Supply Chain Security**: SBOM requirements mandatory
4. **Confidential Computing**: Protected enclaves mainstream
5. **Policy-as-Code**: GitOps for security policies

Would you like me to elaborate on any of these topics?
```

#### Automation

```
You: Create a daily summary of my Azure costs

OpenClaw: I'll help you set up a daily Azure cost summary. Here's the approach:

1. Using Azure Cost Management API
2. Scheduled via Azure Logic Apps or Timer function
3. Delivered to your preferred channel

Would you like me to generate the code for this automation?
```

---

## Multi-Agent: Dedicated Agent per User

OpenClaw allows you to create **multiple agents** on the same instance, each with its own workspace, skills, and personality. A **bindings** system automatically routes Telegram messages to the appropriate agent.

### Why?

Some users (family, colleagues) don't need all of OpenClaw's capabilities. You can create a **restricted** agent that only exposes a single skill via Telegram, with no access to the shell, browsing, or other tools.

### Concrete Example: Restricted Telegram User

A non-technical user uses Telegram on their phone. They send a YouTube link → they receive the video dubbed in French. That's it.

#### 1. Declare the agent in `~/.openclaw/openclaw.json`

```json
{
  "agents": {
    "defaults": {
      "model": { "primary": "azure-apim/gpt-5.2" },
      "workspace": "/home/azureuser/.openclaw/workspace"
    },
    "list": [
      { "id": "main", "default": true },
      {
        "id": "restricted-user",
        "name": "Restricted User",
        "workspace": "/home/azureuser/.openclaw/workspace-restricted",
        "identity": { "name": "Mnemo", "emoji": "🧠" },
        "tools": {}
      }
    ]
  }
}
```

**Key points:**
- Separate `workspace`: the agent only has access to files/skills in that folder
- `tools: {}`: no additional tools (the workspace skills are sufficient)

#### 2. Telegram → Agent Binding

The binding automatically routes a Telegram user's DMs to a specific agent:

```json
{
  "bindings": [
    {
      "agentId": "restricted-user",
      "match": {
        "channel": "telegram",
        "peer": { "kind": "dm", "id": "TELEGRAM_USER_ID" }
      }
    }
  ]
}
```

To find a Telegram user's ID: send `/start` to the bot, then look for `chat.id` in the logs (`journalctl -u openclaw -f`).

#### 3. Restricted Workspace

Create the workspace with a restrictive `SOUL.md`:

```bash
mkdir -p ~/.openclaw/workspace-restricted/skills
```

**`~/.openclaw/workspace-restricted/SOUL.md`** — defines the agent's behavior:
```markdown
# SOUL.md - Restricted Mode

You are Mnemo, in a strictly limited mode for this user.

## Mission
- You do only one thing: dub YouTube videos in French.
- Goal: an ultra-simple experience on mobile.

## Rules
1. If the message contains a YouTube URL: call the yt_fr_dub skill.
2. Otherwise: reply "Just send a YouTube link."
3. Never return commands, JSON, or technical details.
```

#### 4. Skills in the Restricted Workspace

Copy or link only the authorized skills:

```bash
cp -r ~/.openclaw/workspace/skills/yt_fr_dub ~/.openclaw/workspace-restricted/skills/
```

The restricted agent will only have access to skills in its own workspace.

#### 5. Result

| User | Channel | Agent | Capabilities |
|------|---------|-------|-------------|
| Admin | Telegram / TUI | `main` | All tools, shell, browse, skills |
| Restricted user | Telegram DM | `restricted-user` | Only the `yt_fr_dub` skill |

The user sends a YouTube link on Telegram → Mnemo downloads, transcribes, translates, synthesizes voice, remuxes → uploads the MP4 via Managed Identity to Azure Storage → sends back the dubbed video link.

---

## Advanced Configuration

### Custom System Prompt

Customize OpenClaw's behavior by setting a system prompt in `.env`:

```env
SYSTEM_PROMPT="You are a helpful Azure cloud expert assistant. Focus on Azure best practices, security, and cost optimization. Always provide actionable advice."
```

### Memory Configuration

```env
# Conversation memory
MEMORY_TYPE=redis
REDIS_URL=redis://localhost:6379

# Or use simple in-memory storage
MEMORY_TYPE=memory
MAX_MEMORY_MESSAGES=100
```

### Rate Limiting

```env
# Protect against abuse
RATE_LIMIT_ENABLED=true
RATE_LIMIT_REQUESTS=100
RATE_LIMIT_WINDOW_MS=60000
```

### Custom Tools

Create custom tools in `~/openclaw/tools/`:

```javascript
// tools/azure-status.js
export default {
  name: 'azure-status',
  description: 'Check Azure service health status',
  parameters: {
    region: { type: 'string', description: 'Azure region' }
  },
  async execute({ region }) {
    // Your implementation here
    return `Azure status for ${region}: All services operational`;
  }
};
```

Register in `.env`:

```env
CUSTOM_TOOLS_PATH=/home/azureuser/openclaw/tools
```

---

## Monitoring and Logs

### View Logs

```bash
# Follow logs in real-time
journalctl -u openclaw -f

# Last 100 lines
journalctl -u openclaw -n 100

# Logs since last boot
journalctl -u openclaw -b
```

### System Metrics

```bash
# CPU and memory usage
htop

# Disk usage
df -h
```

### Azure Monitor Integration

Enable Azure Monitor for the VM in Azure Portal:
1. VM → **Insights** → **Enable**
2. Configure Log Analytics Workspace
3. View metrics and logs in Azure Portal

### Log Locations

- OpenClaw logs: `journalctl -u openclaw`
- Cloud-init logs: `/var/log/cloud-init-output.log`
- System logs: `/var/log/syslog`

---

## Updating OpenClaw

### Update to Latest Version

```bash
cd ~/openclaw

# Stop current instance
sudo systemctl stop openclaw

# Pull latest code
git pull origin main

# Install dependencies
pnpm install

# Start updated version
sudo systemctl start openclaw

# Verify
systemctl status openclaw
```

### Backup Before Update

```bash
# Backup configuration
cp .env .env.backup

# Backup data
tar -czf ~/openclaw-backup-$(date +%Y%m%d).tar.gz ~/openclaw/data
```

### Rollback

```bash
# Restore configuration
cp .env.backup .env

# Checkout previous version
git checkout <previous-commit>

# Restart
sudo systemctl restart openclaw
```

---

## Common Tasks

### Restart OpenClaw

```bash
sudo systemctl restart openclaw
```

### Check Status

```bash
systemctl status openclaw
journalctl -u openclaw --no-pager -n 50
```

### Clear Conversation History

```bash
cd ~/openclaw && npm run clear-history
```

### Stop OpenClaw

```bash
sudo systemctl stop openclaw
```

### Factory Reset

```bash
cd ~/openclaw
sudo systemctl stop openclaw
rm -rf data/
rm .env
cp .env.example .env
# Reconfigure as needed
sudo systemctl start openclaw
```

---

## Next Steps

- [Security Guide](SECURITY.md) - Harden your deployment
- [Troubleshooting](TROUBLESHOOTING.md) - Solve common issues
- [OpenClaw Documentation](https://github.com/openclaw/openclaw/wiki) - Full feature documentation
