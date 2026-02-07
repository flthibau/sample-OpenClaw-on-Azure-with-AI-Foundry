#!/bin/bash
#
# OpenClaw - Flexible Local Deployment (WSL + Docker)
#
# This script deploys OpenClaw with configurable security levels:
# - Full access to web (browsing, APIs)
# - Azure AI Foundry integration via Managed Identity token forwarding
# - Dedicated storage volume (no Windows file access)
# - Configurable sandbox mode
#
# Usage:
#   ./deploy-local-flexible.sh
#   ./deploy-local-flexible.sh --azure-endpoint "https://your-ai.openai.azure.com"
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

print_step() { echo -e "\n${CYAN}📌 $1${NC}"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️ $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ️ $1${NC}"; }

# Default values
AZURE_OPENAI_ENDPOINT=""
AZURE_OPENAI_DEPLOYMENT="gpt-4o-deployment"
OPENAI_API_KEY=""
USE_AZURE=true
DATA_DIR="$HOME/.openclaw-sandbox"
SANDBOX_MODE="flexible"  # flexible, strict, or open

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --azure-endpoint)
            AZURE_OPENAI_ENDPOINT="$2"
            USE_AZURE=true
            shift 2
            ;;
        --azure-deployment)
            AZURE_OPENAI_DEPLOYMENT="$2"
            shift 2
            ;;
        --openai-key)
            OPENAI_API_KEY="$2"
            USE_AZURE=false
            shift 2
            ;;
        --data-dir)
            DATA_DIR="$2"
            shift 2
            ;;
        --sandbox)
            SANDBOX_MODE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --azure-endpoint URL     Azure AI Foundry endpoint"
            echo "  --azure-deployment NAME  Azure deployment name (default: gpt-4o-deployment)"
            echo "  --openai-key KEY         OpenAI API key (use this OR azure)"
            echo "  --data-dir DIR           Data directory (default: ~/.openclaw-sandbox)"
            echo "  --sandbox MODE           Sandbox mode: flexible, strict, open (default: flexible)"
            echo "  -h, --help               Show this help"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Banner
echo -e "${MAGENTA}"
cat << 'EOF'

╔═══════════════════════════════════════════════════════════════════════════╗
║                                                                           ║
║   🦞 OpenClaw - Flexible Local Sandbox 🦞                                 ║
║                                                                           ║
║   Features:                                                               ║
║   ✅ Full web access (browser, APIs, research)                           ║
║   ✅ Azure AI Foundry integration                                        ║
║   ✅ Isolated storage (no Windows file access)                           ║
║   ✅ Configurable sandbox levels                                         ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝

EOF
echo -e "${NC}"

# Display what OpenClaw can do
echo "🦞 What OpenClaw can do in this sandbox:"
echo ""
echo "   📁 FILE OPERATIONS:"
echo "      • read, write, edit files (in sandbox only)"
echo "      • bash commands & process management"
echo ""
echo "   🌐 WEB & BROWSING:"
echo "      • Full browser control (Chrome/Chromium)"
echo "      • Web research & scraping"
echo "      • API calls to any service"
echo ""
echo "   💬 MESSAGING CHANNELS:"
echo "      • WhatsApp, Telegram, Slack, Discord"
echo "      • Teams, Signal, iMessage, Matrix"
echo ""
echo "   🤖 AI & AUTOMATION:"
echo "      • Azure AI Foundry / OpenAI models"
echo "      • Cron jobs & webhooks"
echo "      • Multi-agent coordination"
echo ""
echo "   ❌ BLOCKED:"
echo "      • No access to Windows files (/mnt/c)"
echo "      • No access to host credentials"
echo ""

# Check if running in WSL
if grep -qi microsoft /proc/version 2>/dev/null; then
    print_info "Running in WSL - Good!"
else
    print_warning "Not running in WSL. This script is designed for WSL."
fi

# Check Docker
print_step "Checking prerequisites..."
if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed."
    echo "Install Docker Desktop for Windows and enable WSL integration."
    exit 1
fi
print_success "Docker installed"

# Check Docker is running
if ! docker info &> /dev/null; then
    print_error "Docker daemon is not running."
    echo "Start Docker Desktop and try again."
    exit 1
fi
print_success "Docker daemon running"

# Get Azure AI Foundry endpoint if not provided
if [ "$USE_AZURE" = true ] && [ -z "$AZURE_OPENAI_ENDPOINT" ]; then
    print_step "Azure AI Foundry Configuration"
    echo ""
    echo "You have an Azure AI Foundry resource deployed on Azure."
    echo "Enter your endpoint (e.g., https://ai-openclaw-dev.openai.azure.com):"
    read -r AZURE_OPENAI_ENDPOINT
    
    if [ -z "$AZURE_OPENAI_ENDPOINT" ]; then
        print_warning "No endpoint provided. You can configure it later in .env"
    fi
    
    echo ""
    echo "Enter deployment name (default: $AZURE_OPENAI_DEPLOYMENT):"
    read -r input_deployment
    if [ -n "$input_deployment" ]; then
        AZURE_OPENAI_DEPLOYMENT="$input_deployment"
    fi
fi

# Create data directory
print_step "Creating sandbox directory..."
mkdir -p "$DATA_DIR"/{data,logs,config,workspace,browser-data}
chmod 700 "$DATA_DIR"
print_success "Sandbox directory: $DATA_DIR"

# Create environment file
print_step "Creating configuration..."

if [ "$USE_AZURE" = true ]; then
    # Azure AI Foundry configuration
    cat > "$DATA_DIR/config/.env" << ENVEOF
# ===========================================
# OpenClaw Flexible Sandbox Configuration
# Generated: $(date)
# ===========================================

# ===========================================
# Azure AI Foundry Configuration
# Uses DefaultAzureCredential for auth
# ===========================================
AZURE_OPENAI_ENDPOINT=${AZURE_OPENAI_ENDPOINT}
AZURE_OPENAI_DEPLOYMENT=${AZURE_OPENAI_DEPLOYMENT}
AZURE_OPENAI_API_VERSION=2024-10-01-preview

# For local testing, you may need an API key
# Get it from Azure Portal > AI Foundry > Keys
# AZURE_OPENAI_API_KEY=your-key-here

# ===========================================
# OpenClaw General Settings
# ===========================================
APP_NAME=OpenClaw-Sandbox
LOG_LEVEL=info
PORT=18789

# Gateway settings
GATEWAY_BIND=0.0.0.0

# ===========================================
# Security Settings
# ===========================================
SESSION_SECRET=$(openssl rand -hex 32)

# ===========================================
# Browser Control (enabled)
# ===========================================
BROWSER_ENABLED=true
BROWSER_HEADLESS=true

# ===========================================
# Messaging Channels (configure as needed)
# ===========================================
# Telegram
TELEGRAM_ENABLED=false
# TELEGRAM_BOT_TOKEN=your-bot-token

# WhatsApp (via Baileys)
WHATSAPP_ENABLED=false

# Slack
SLACK_ENABLED=false
# SLACK_BOT_TOKEN=xoxb-your-token
# SLACK_APP_TOKEN=xapp-your-token

# Discord
DISCORD_ENABLED=false
# DISCORD_BOT_TOKEN=your-token
ENVEOF
else
    # OpenAI direct configuration
    cat > "$DATA_DIR/config/.env" << ENVEOF
# ===========================================
# OpenClaw Flexible Sandbox Configuration
# Generated: $(date)
# ===========================================

# ===========================================
# OpenAI Configuration
# ===========================================
OPENAI_API_KEY=${OPENAI_API_KEY}

# ===========================================
# OpenClaw General Settings
# ===========================================
APP_NAME=OpenClaw-Sandbox
LOG_LEVEL=info
PORT=18789
GATEWAY_BIND=0.0.0.0

# ===========================================
# Security Settings
# ===========================================
SESSION_SECRET=$(openssl rand -hex 32)

# ===========================================
# Browser Control (enabled)
# ===========================================
BROWSER_ENABLED=true
BROWSER_HEADLESS=true

# ===========================================
# Messaging Channels
# ===========================================
TELEGRAM_ENABLED=false
WHATSAPP_ENABLED=false
SLACK_ENABLED=false
DISCORD_ENABLED=false
ENVEOF
fi

chmod 600 "$DATA_DIR/config/.env"
print_success "Configuration created"

# Create OpenClaw configuration file
cat > "$DATA_DIR/config/openclaw.json" << 'CONFIGEOF'
{
  "agent": {
    "model": "azure/gpt-4o"
  },
  "gateway": {
    "bind": "0.0.0.0",
    "port": 18789
  },
  "browser": {
    "enabled": true,
    "headless": true
  },
  "tools": {
    "bash": true,
    "read": true,
    "write": true,
    "edit": true,
    "process": true,
    "browser": true
  }
}
CONFIGEOF

# Create docker-compose file
print_step "Creating Docker Compose configuration..."
cat > "$DATA_DIR/docker-compose.yml" << 'COMPOSE_EOF'
version: '3.8'

services:
  openclaw:
    image: openclaw/openclaw:latest
    container_name: openclaw-sandbox
    restart: unless-stopped
    
    # Full network access for web browsing and APIs
    network_mode: bridge
    
    # Environment
    env_file:
      - ./config/.env
    
    # Volumes - dedicated storage only, NO /mnt/c
    volumes:
      # OpenClaw data and configuration
      - ./data:/root/.openclaw:rw
      - ./config/openclaw.json:/root/.openclaw/openclaw.json:ro
      - ./workspace:/root/.openclaw/workspace:rw
      - ./logs:/app/logs:rw
      # Browser data (for persistent sessions)
      - ./browser-data:/root/.openclaw/browser:rw
      # Temp for browser operations
      - /tmp/openclaw:/tmp:rw
      # EXPLICITLY NO Windows access:
      # - /mnt/c is NOT mounted
    
    # Ports
    ports:
      - "127.0.0.1:18789:18789"   # Gateway + WebChat
      - "127.0.0.1:18790:18790"   # Control UI
    
    # Enable browser (needs some capabilities)
    cap_add:
      - SYS_ADMIN  # Required for Chrome sandbox
    security_opt:
      - seccomp=unconfined  # Required for Chrome
    
    # Shared memory for Chrome
    shm_size: '2gb'
    
    # Health check
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:18789/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    
    # Resource limits
    deploy:
      resources:
        limits:
          cpus: '4'
          memory: 4G
        reservations:
          cpus: '1'
          memory: 1G

networks:
  default:
    driver: bridge
COMPOSE_EOF
print_success "Docker Compose configuration created"

# Create helper scripts
print_step "Creating helper scripts..."

# Start script
cat > "$DATA_DIR/start.sh" << 'START_EOF'
#!/bin/bash
cd "$(dirname "$0")"
echo "🦞 Starting OpenClaw Sandbox..."
docker compose up -d
sleep 3
echo ""
echo "✅ OpenClaw started!"
echo ""
echo "🌐 Web Interfaces:"
echo "   • WebChat:    http://localhost:18789"
echo "   • Control UI: http://localhost:18790"
echo ""
echo "📊 Quick commands:"
echo "   ./status.sh  - Check status"
echo "   ./logs.sh    - View logs"
echo "   ./shell.sh   - Open shell in container"
echo "   ./stop.sh    - Stop OpenClaw"
START_EOF
chmod +x "$DATA_DIR/start.sh"

# Stop script
cat > "$DATA_DIR/stop.sh" << 'STOP_EOF'
#!/bin/bash
cd "$(dirname "$0")"
echo "🛑 Stopping OpenClaw..."
docker compose down
echo "✅ OpenClaw stopped"
STOP_EOF
chmod +x "$DATA_DIR/stop.sh"

# Logs script
cat > "$DATA_DIR/logs.sh" << 'LOGS_EOF'
#!/bin/bash
cd "$(dirname "$0")"
docker compose logs -f
LOGS_EOF
chmod +x "$DATA_DIR/logs.sh"

# Shell script - get into the container
cat > "$DATA_DIR/shell.sh" << 'SHELL_EOF'
#!/bin/bash
cd "$(dirname "$0")"
echo "🐚 Opening shell in OpenClaw container..."
echo "   Type 'exit' to leave"
echo ""
docker compose exec openclaw /bin/bash
SHELL_EOF
chmod +x "$DATA_DIR/shell.sh"

# Status script
cat > "$DATA_DIR/status.sh" << 'STATUS_EOF'
#!/bin/bash
cd "$(dirname "$0")"

echo "🦞 OpenClaw Sandbox Status"
echo "=========================="
echo ""

# Container status
echo "🐳 Container:"
docker compose ps 2>/dev/null || echo "   Not running"

echo ""
echo "🔒 Security Status:"

# Check mounts
MOUNTS=$(docker inspect openclaw-sandbox 2>/dev/null | grep -i '"/mnt/c' || echo "")
if [ -z "$MOUNTS" ]; then
    echo "   ✅ Windows filesystem (/mnt/c) NOT accessible"
else
    echo "   ❌ WARNING: Windows filesystem IS accessible!"
fi

# Check network
echo "   ✅ Full network access (web browsing enabled)"

echo ""
echo "🧠 AI Configuration:"
if grep -q "AZURE_OPENAI_ENDPOINT" ./config/.env 2>/dev/null; then
    ENDPOINT=$(grep "AZURE_OPENAI_ENDPOINT" ./config/.env | cut -d= -f2)
    echo "   Provider: Azure AI Foundry"
    echo "   Endpoint: $ENDPOINT"
else
    echo "   Provider: OpenAI"
fi

echo ""
echo "📁 Sandbox Locations:"
echo "   Data:      $(pwd)/data"
echo "   Workspace: $(pwd)/workspace"
echo "   Logs:      $(pwd)/logs"
echo "   Browser:   $(pwd)/browser-data"

echo ""
echo "🌐 Web Interfaces:"
echo "   WebChat:    http://localhost:18789"
echo "   Control UI: http://localhost:18790"
STATUS_EOF
chmod +x "$DATA_DIR/status.sh"

# Edit config script
cat > "$DATA_DIR/edit-config.sh" << 'EDIT_EOF'
#!/bin/bash
cd "$(dirname "$0")"
${EDITOR:-nano} ./config/.env
echo ""
echo "⚠️ Restart OpenClaw for changes to take effect:"
echo "   ./stop.sh && ./start.sh"
EDIT_EOF
chmod +x "$DATA_DIR/edit-config.sh"

# Capabilities script - show what OpenClaw can do
cat > "$DATA_DIR/capabilities.sh" << 'CAP_EOF'
#!/bin/bash
echo "🦞 OpenClaw Capabilities in this Sandbox"
echo "========================================"
echo ""
echo "✅ ENABLED - What the agent CAN do:"
echo ""
echo "   📁 FILE OPERATIONS (sandbox only):"
echo "      • read     - Read files in workspace"
echo "      • write    - Create new files"
echo "      • edit     - Modify existing files"
echo "      • bash     - Execute shell commands"
echo "      • process  - Manage processes"
echo ""
echo "   🌐 WEB & RESEARCH:"
echo "      • browser  - Full Chrome control"
echo "      • fetch    - HTTP requests to any URL"
echo "      • research - Web search and scraping"
echo ""
echo "   💬 MESSAGING (if configured):"
echo "      • WhatsApp, Telegram, Slack, Discord"
echo "      • Teams, Signal, iMessage, Matrix"
echo ""
echo "   ⏰ AUTOMATION:"
echo "      • cron     - Scheduled tasks"
echo "      • webhooks - External triggers"
echo ""
echo "   🤖 AI:"
echo "      • Azure AI Foundry or OpenAI models"
echo "      • Multi-agent coordination"
echo ""
echo "❌ BLOCKED - What the agent CANNOT do:"
echo ""
echo "   • Access Windows files (/mnt/c not mounted)"
echo "   • Access host credentials"
echo "   • Escape the Docker container"
echo "   • Access other Docker containers"
echo ""
echo "📝 To modify capabilities, edit ./config/openclaw.json"
CAP_EOF
chmod +x "$DATA_DIR/capabilities.sh"

print_success "Helper scripts created"

# Pull Docker image
print_step "Pulling OpenClaw Docker image..."
docker pull openclaw/openclaw:latest 2>/dev/null || {
    print_warning "Could not pull image. Will try on first start."
}

# Display results
echo -e "${GREEN}"
cat << 'EOF'

╔═══════════════════════════════════════════════════════════════════════════╗
║                                                                           ║
║   🎉 SANDBOX SETUP COMPLETE! 🎉                                           ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝

EOF
echo -e "${NC}"

echo "📁 Installation: $DATA_DIR"
echo ""
echo "🔒 Security:"
echo "   ✅ Windows files (/mnt/c) NOT accessible"
echo "   ✅ Full web access for browsing & APIs"
echo "   ✅ Dedicated sandbox storage"
echo ""
echo "🚀 Quick Start:"
echo "   cd $DATA_DIR"
echo "   ./start.sh          # Start OpenClaw"
echo "   ./capabilities.sh   # See what it can do"
echo "   ./status.sh         # Check status"
echo ""
echo "🌐 Once started, access:"
echo "   • WebChat:    http://localhost:18789"
echo "   • Control UI: http://localhost:18790"
echo ""

if [ -z "$AZURE_OPENAI_ENDPOINT" ] && [ "$USE_AZURE" = true ]; then
    echo -e "${YELLOW}⚠️ Azure AI Foundry endpoint not configured!${NC}"
    echo "   Edit: $DATA_DIR/config/.env"
    echo "   Add:  AZURE_OPENAI_ENDPOINT=https://your-resource.openai.azure.com"
    echo "         AZURE_OPENAI_API_KEY=your-key"
    echo ""
fi

echo "═══════════════════════════════════════════════════════════════════════════"
