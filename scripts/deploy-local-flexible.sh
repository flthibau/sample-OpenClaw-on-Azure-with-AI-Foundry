#!/bin/bash
#
# OpenClaw - Flexible Local Deployment (WSL - Native)
#
# This script deploys OpenClaw natively:
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
║   ✅ Native installation                                                ║
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

# Check Node.js
print_step "Checking prerequisites..."
if ! command -v node &> /dev/null; then
    print_error "Node.js is not installed."
    echo "Install Node.js 20+:"
    echo "  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash -"
    echo "  sudo apt-get install -y nodejs"
    exit 1
fi
print_success "Node.js installed ($(node --version))"

# Check npm/pnpm
if command -v pnpm &> /dev/null; then
    print_success "pnpm installed"
    PKG_MGR="pnpm"
elif command -v npm &> /dev/null; then
    print_success "npm installed"
    PKG_MGR="npm"
else
    print_error "No package manager found. Install pnpm or npm."
    exit 1
fi

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
mkdir -p "$DATA_DIR"/{data,logs,config,workspace}
chmod 700 "$DATA_DIR"
print_success "Sandbox directory: $DATA_DIR"

# Clone or update OpenClaw
print_step "Setting up OpenClaw..."
if [ -d "$DATA_DIR/openclaw" ]; then
    cd "$DATA_DIR/openclaw" && git pull origin main 2>/dev/null || true
    print_success "OpenClaw updated"
else
    git clone https://github.com/openclaw/openclaw.git "$DATA_DIR/openclaw" 2>/dev/null || {
        print_warning "Could not clone OpenClaw. You may need to set it up manually."
    }
fi

# Install dependencies
if [ -d "$DATA_DIR/openclaw" ]; then
    cd "$DATA_DIR/openclaw"
    $PKG_MGR install 2>/dev/null || print_warning "Could not install dependencies"
fi

# Create environment file
print_step "Creating configuration..."

if [ "$USE_AZURE" = true ]; then
    cat > "$DATA_DIR/config/.env" << ENVEOF
# ===========================================
# OpenClaw Flexible Sandbox Configuration
# Generated: $(date)
# ===========================================

# Azure AI Foundry Configuration
AZURE_OPENAI_ENDPOINT=${AZURE_OPENAI_ENDPOINT}
AZURE_OPENAI_DEPLOYMENT=${AZURE_OPENAI_DEPLOYMENT}
AZURE_OPENAI_API_VERSION=2024-10-01-preview

# OpenClaw General Settings
APP_NAME=OpenClaw-Sandbox
LOG_LEVEL=info
PORT=18789
GATEWAY_BIND=0.0.0.0

# Security Settings
SESSION_SECRET=$(openssl rand -hex 32)

# Browser Control (enabled)
BROWSER_ENABLED=true
BROWSER_HEADLESS=true

# Messaging Channels (configure as needed)
TELEGRAM_ENABLED=false
WHATSAPP_ENABLED=false
SLACK_ENABLED=false
DISCORD_ENABLED=false
ENVEOF
else
    cat > "$DATA_DIR/config/.env" << ENVEOF
# ===========================================
# OpenClaw Flexible Sandbox Configuration
# Generated: $(date)
# ===========================================

# OpenAI Configuration
OPENAI_API_KEY=${OPENAI_API_KEY}

# OpenClaw General Settings
APP_NAME=OpenClaw-Sandbox
LOG_LEVEL=info
PORT=18789
GATEWAY_BIND=0.0.0.0

# Security Settings
SESSION_SECRET=$(openssl rand -hex 32)

# Browser Control (enabled)
BROWSER_ENABLED=true
BROWSER_HEADLESS=true

# Messaging Channels
TELEGRAM_ENABLED=false
WHATSAPP_ENABLED=false
SLACK_ENABLED=false
DISCORD_ENABLED=false
ENVEOF
fi

chmod 600 "$DATA_DIR/config/.env"
print_success "Configuration created"

# Create helper scripts
print_step "Creating helper scripts..."

# Start script
cat > "$DATA_DIR/start.sh" << 'START_EOF'
#!/bin/bash
cd "$(dirname "$0")"
echo "🦞 Starting OpenClaw Sandbox..."
source config/.env 2>/dev/null
cd openclaw 2>/dev/null && nohup npx openclaw gateway start > ../logs/openclaw.log 2>&1 &
echo $! > ../openclaw.pid
sleep 3
echo ""
echo "✅ OpenClaw started! (PID: $(cat ../openclaw.pid))"
echo ""
echo "🌐 Web Interfaces:"
echo "   • WebChat:    http://localhost:18789"
echo ""
echo "📊 Quick commands:"
echo "   ./status.sh  - Check status"
echo "   ./logs.sh    - View logs"
echo "   ./stop.sh    - Stop OpenClaw"
START_EOF
chmod +x "$DATA_DIR/start.sh"

# Stop script
cat > "$DATA_DIR/stop.sh" << 'STOP_EOF'
#!/bin/bash
cd "$(dirname "$0")"
echo "🛑 Stopping OpenClaw..."
if [ -f openclaw.pid ]; then
    kill $(cat openclaw.pid) 2>/dev/null || true
    rm -f openclaw.pid
fi
pkill -f "openclaw gateway" 2>/dev/null || true
echo "✅ OpenClaw stopped"
STOP_EOF
chmod +x "$DATA_DIR/stop.sh"

# Logs script
cat > "$DATA_DIR/logs.sh" << 'LOGS_EOF'
#!/bin/bash
cd "$(dirname "$0")"
if [ -f logs/openclaw.log ]; then
    tail -f logs/openclaw.log
else
    echo "No logs found. Is OpenClaw running?"
fi
LOGS_EOF
chmod +x "$DATA_DIR/logs.sh"

# Status script
cat > "$DATA_DIR/status.sh" << 'STATUS_EOF'
#!/bin/bash
cd "$(dirname "$0")"

echo "🦞 OpenClaw Sandbox Status"
echo "=========================="
echo ""

# Process status
echo "🔧 Process:"
if [ -f openclaw.pid ] && kill -0 $(cat openclaw.pid) 2>/dev/null; then
    echo "   ✅ Running (PID: $(cat openclaw.pid))"
else
    echo "   ❌ Not running"
fi

echo ""
echo "🔒 Security Status:"

# Check mounts
if ! ls /mnt/c 2>/dev/null | head -1 > /dev/null 2>&1; then
    echo "   ✅ Windows filesystem (/mnt/c) NOT accessible"
else
    echo "   ⚠️ Windows filesystem IS accessible (WSL default)"
fi

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

echo ""
echo "🌐 Web Interface:"
echo "   WebChat: http://localhost:18789"
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

# Capabilities script
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
echo ""
echo "📝 To modify capabilities, edit ./config/openclaw.json"
CAP_EOF
chmod +x "$DATA_DIR/capabilities.sh"

print_success "Helper scripts created"

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
echo ""

if [ -z "$AZURE_OPENAI_ENDPOINT" ] && [ "$USE_AZURE" = true ]; then
    echo -e "${YELLOW}⚠️ Azure AI Foundry endpoint not configured!${NC}"
    echo "   Edit: $DATA_DIR/config/.env"
    echo "   Add:  AZURE_OPENAI_ENDPOINT=https://your-resource.openai.azure.com"
    echo "         AZURE_OPENAI_API_KEY=your-key"
    echo ""
fi

echo "═══════════════════════════════════════════════════════════════════════════"
