# Secure Local Deployment (WSL)

This guide explains how to deploy OpenClaw locally on Windows via WSL in a secure manner.

## 🔒 Security Features

| Feature | Description |
|---------|-------------|
| **File isolation** | No access to `/mnt/c` (Windows files) |
| **Dedicated volume** | Storage in `~/.openclaw-secure` only |
| **Resource limits** | Configurable via systemd |
| **Restricted network** | HTTP/HTTPS only |

## 📋 Prerequisites

1. **Windows 10/11** with WSL2 installed
2. **Node.js 20+** installed in WSL
3. **OpenAI API key** (or Azure OpenAI)

## 🚀 Installation

### 1. Open WSL

```powershell
wsl
```

### 2. Run the deployment script

```bash
cd /path/to/sample-OpenClaw-on-Azure-with-AI-Foundry/scripts

chmod +x deploy-local-secure.sh
./deploy-local-secure.sh --openai-key "sk-your-key"
```

### 3. Ready!

OpenClaw is accessible at: http://localhost:18789

## 📂 File Structure

```
~/.openclaw-secure/
├── config/
│   └── .env              # OpenClaw configuration (API keys, etc.)
├── data/                 # Persistent data (memory)
├── logs/                 # Application logs
├── start.sh              # Start OpenClaw
├── stop.sh               # Stop OpenClaw
├── status.sh             # Check status + security
├── logs.sh               # View logs
└── edit-config.sh        # Edit configuration
```

## 🛠️ Commands

```bash
cd ~/.openclaw-secure

# Start
./start.sh

# Stop
./stop.sh

# Check status and security
./status.sh

# View logs
./logs.sh

# Edit configuration
./edit-config.sh
```

## ⚙️ Configuration

### OpenAI API

Edit `~/.openclaw-secure/config/.env`:

```env
OPENAI_API_KEY=sk-your-openai-key
```

### WhatsApp (via Twilio)

```env
WHATSAPP_ENABLED=true
TWILIO_ACCOUNT_SID=your-sid
TWILIO_AUTH_TOKEN=your-token
TWILIO_WHATSAPP_NUMBER=+14155238886
```

### Telegram

```env
TELEGRAM_ENABLED=true
TELEGRAM_BOT_TOKEN=123456789:ABCdefGHIjklMNOpqrsTUVwxyz
```

After editing, restart:
```bash
./stop.sh && ./start.sh
```

## 🔒 Security Verification

```bash
./status.sh
```

Expected output:
```
📊 OpenClaw Secure Status
=========================

🔧 Service:
● openclaw.service - OpenClaw Gateway Service
     Active: active (running)

🔒 Security Check:
   ✅ No Windows filesystem access
   ✅ Network restricted to HTTP/HTTPS
```

## 🆚 Comparison: Local vs Azure

| Aspect | Local (WSL) | Azure VM |
|--------|-------------|----------|
| **Cost** | ✅ Free | ⚠️ ~$70/month |
| **Isolation** | ⚠️ Good (WSL) | ✅ Full |
| **Windows access** | ❌ Blocked | ✅ Impossible |
| **Performance** | Depends on your PC | Consistent |
| **Availability** | When PC is on | 24/7 |
| **Network** | HTTP/HTTPS | Isolated VNet |

## ⚠️ Limitations

1. **No full network isolation**: The process can access the Internet (HTTP/HTTPS)
2. **Same machine**: A kernel exploit could theoretically escape

For maximum security, prefer the Azure deployment.

## 🔧 Troubleshooting

### Permission error

```bash
sudo chown -R $USER:$USER ~/.openclaw-secure
chmod 700 ~/.openclaw-secure
```

### Service won't start

```bash
journalctl -u openclaw -f
# Or check the logs directly
cat ~/.openclaw-secure/logs/*.log
```
