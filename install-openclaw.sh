#!/bin/bash
# Installation script for OpenClaw on Azure VM

echo "=== Updating system ==="
sudo apt-get update && sudo apt-get upgrade -y

echo "=== Installing Node.js 22 ==="
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs

echo "=== Verifying Node.js installation ==="
node --version
npm --version

echo "=== Installing OpenClaw ==="
sudo npm install -g openclaw@latest

echo "=== Creating OpenClaw config directory ==="
mkdir -p ~/.config/openclaw

echo "=== OpenClaw installation complete! ==="
openclaw --version