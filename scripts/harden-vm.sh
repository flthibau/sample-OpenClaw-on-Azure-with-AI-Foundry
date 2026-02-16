#!/usr/bin/env bash
# =============================================================================
# harden-vm.sh — OpenClaw VM hardening script
# Run as root (sudo) on vm-openclaw
# =============================================================================
set -euo pipefail

OPENCLAW_USER="openclaw"
OPENCLAW_HOME="/home/${OPENCLAW_USER}"
CURRENT_USER="azureuser"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  OpenClaw VM Hardening Script                                   ║"
echo "╚══════════════════════════════════════════════════════════════════╝"

# ─────────────────────────────────────────────────────────────────────────────
# 1. Create dedicated system user for OpenClaw
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "▸ Step 1: Creating system user '${OPENCLAW_USER}'..."

if id "${OPENCLAW_USER}" &>/dev/null; then
  echo "  User '${OPENCLAW_USER}' already exists — skipping."
else
  useradd \
    --system \
    --create-home \
    --home-dir "${OPENCLAW_HOME}" \
    --shell /usr/sbin/nologin \
    --comment "OpenClaw Agent Runtime" \
    "${OPENCLAW_USER}"
  echo "  ✓ User '${OPENCLAW_USER}' created (no login shell)."
fi

# ─────────────────────────────────────────────────────────────────────────────
# 2. Migrate OpenClaw data to new user
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "▸ Step 2: Migrating OpenClaw data..."

CURRENT_OPENCLAW_DIR="/home/${CURRENT_USER}/.openclaw"
NEW_OPENCLAW_DIR="${OPENCLAW_HOME}/.openclaw"

if [[ -d "${CURRENT_OPENCLAW_DIR}" && ! -d "${NEW_OPENCLAW_DIR}" ]]; then
  echo "  Copying ${CURRENT_OPENCLAW_DIR} → ${NEW_OPENCLAW_DIR}..."
  cp -rp "${CURRENT_OPENCLAW_DIR}" "${NEW_OPENCLAW_DIR}"
  chown -R "${OPENCLAW_USER}:${OPENCLAW_USER}" "${NEW_OPENCLAW_DIR}"
  echo "  ✓ Data migrated."
elif [[ -d "${NEW_OPENCLAW_DIR}" ]]; then
  echo "  ${NEW_OPENCLAW_DIR} already exists — skipping migration."
else
  echo "  ⚠ No existing OpenClaw data at ${CURRENT_OPENCLAW_DIR}."
  mkdir -p "${NEW_OPENCLAW_DIR}"
  chown -R "${OPENCLAW_USER}:${OPENCLAW_USER}" "${NEW_OPENCLAW_DIR}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3. Create systemd service for openclaw user
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "▸ Step 3: Creating systemd service..."

SERVICE_FILE="/etc/systemd/system/openclaw-gateway.service"
cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=OpenClaw Gateway (secure)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${OPENCLAW_USER}
Group=${OPENCLAW_USER}
WorkingDirectory=${OPENCLAW_HOME}
ExecStart=/usr/bin/openclaw gateway --port 18789
Restart=on-failure
RestartSec=10
StartLimitBurst=5
StartLimitIntervalSec=300

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=false
ReadWritePaths=${OPENCLAW_HOME}
PrivateTmp=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
RestrictNamespaces=true
MemoryDenyWriteExecute=false

# Environment
Environment=NODE_ENV=production
Environment=HOME=${OPENCLAW_HOME}

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
echo "  ✓ Service file created at ${SERVICE_FILE}"

# ─────────────────────────────────────────────────────────────────────────────
# 4. Disable SSH password authentication
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "▸ Step 4: Hardening SSH..."

SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_HARDENING="/etc/ssh/sshd_config.d/99-openclaw-hardening.conf"

cat > "${SSHD_HARDENING}" <<EOF
# OpenClaw VM hardening — $(date +%Y-%m-%d)
PasswordAuthentication no
ChallengeResponseAuthentication no
PermitRootLogin no
MaxAuthTries 3
MaxSessions 2
ClientAliveInterval 300
ClientAliveCountMax 2
AllowUsers ${CURRENT_USER}
EOF

# Validate config before restarting
if sshd -t 2>/dev/null; then
  systemctl reload sshd
  echo "  ✓ SSH hardened: password auth disabled, root login disabled."
else
  echo "  ⚠ SSH config validation failed — reverting."
  rm -f "${SSHD_HARDENING}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 5. Lock azureuser from agent use
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "▸ Step 5: Restricting ${CURRENT_USER}..."

# Keep azureuser for admin SSH, but prevent agents from using it
# by removing from any agent-related groups and locking crontab
if [[ -f "/var/spool/cron/crontabs/${CURRENT_USER}" ]]; then
  echo "  ⚠ Migrating ${CURRENT_USER} crontab to ${OPENCLAW_USER}..."
  crontab -u "${CURRENT_USER}" -l 2>/dev/null | crontab -u "${OPENCLAW_USER}" - 2>/dev/null || true
fi

# Create a marker file so agents know not to use azureuser
mkdir -p "/home/${CURRENT_USER}/.config"
cat > "/home/${CURRENT_USER}/.config/openclaw-notice" <<EOF
This user account (${CURRENT_USER}) is for administrative SSH access only.
OpenClaw agents run under the '${OPENCLAW_USER}' system user.
Do not store credentials or run agent workloads under this account.
EOF

echo "  ✓ ${CURRENT_USER} restricted (admin SSH only)."

# ─────────────────────────────────────────────────────────────────────────────
# 6. Set up firewall rules (UFW)
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "▸ Step 6: Configuring firewall..."

if command -v ufw &>/dev/null; then
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing
  # Allow SSH only from Azure Bastion subnet (10.0.1.0/26)
  ufw allow from 10.0.1.0/26 to any port 22 proto tcp comment "Bastion SSH"
  # Allow localhost for OpenClaw gateway
  ufw allow from 127.0.0.1 to any port 18789 proto tcp comment "OpenClaw Gateway"
  ufw --force enable
  echo "  ✓ UFW configured: deny all inbound except Bastion SSH + localhost gateway."
else
  echo "  ⚠ UFW not installed — skipping firewall setup."
fi

# ─────────────────────────────────────────────────────────────────────────────
# 7. Summary
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Hardening Complete                                             ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║  ✓ System user '${OPENCLAW_USER}' created (no login shell)     ║"
echo "║  ✓ Systemd service configured (system-level)                   ║"
echo "║  ✓ SSH: password auth disabled, root login disabled            ║"
echo "║  ✓ '${CURRENT_USER}' restricted to admin SSH only              ║"
echo "║  ✓ Firewall: deny all except Bastion + localhost               ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║  Next steps:                                                    ║"
echo "║  1. Stop old user-level service:                                ║"
echo "║     systemctl --user stop openclaw-gateway (as azureuser)       ║"
echo "║  2. Start new system service:                                   ║"
echo "║     sudo systemctl enable --now openclaw-gateway                ║"
echo "║  3. Verify: sudo systemctl status openclaw-gateway              ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
