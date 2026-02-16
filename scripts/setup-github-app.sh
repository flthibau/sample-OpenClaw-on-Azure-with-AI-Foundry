#!/usr/bin/env bash
# =============================================================================
# setup-github-app.sh — Bootstrap GitHub App for OpenClaw
# Creates the Key Vault secret and tests the full token flow
# =============================================================================
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Configuration — fill these in or pass as environment variables
# ─────────────────────────────────────────────────────────────────────────────
GITHUB_APP_ID="${GITHUB_APP_ID:?Set GITHUB_APP_ID}"
GITHUB_INSTALLATION_ID="${GITHUB_INSTALLATION_ID:?Set GITHUB_INSTALLATION_ID}"
KEY_VAULT_NAME="${KEY_VAULT_NAME:-kv-openclaw}"
SECRET_NAME="${SECRET_NAME:-github-app-pem}"
PEM_FILE="${1:?Usage: $0 <path-to-pem-file>}"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  GitHub App Setup for OpenClaw                                  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""
echo "  App ID:           ${GITHUB_APP_ID}"
echo "  Installation ID:  ${GITHUB_INSTALLATION_ID}"
echo "  Key Vault:        ${KEY_VAULT_NAME}"
echo "  Secret Name:      ${SECRET_NAME}"
echo "  PEM File:         ${PEM_FILE}"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 1. Validate PEM file
# ─────────────────────────────────────────────────────────────────────────────
echo "▸ Step 1: Validating PEM file..."
if [[ ! -f "${PEM_FILE}" ]]; then
  echo "  ✗ PEM file not found: ${PEM_FILE}"
  exit 1
fi

if ! head -1 "${PEM_FILE}" | grep -q "BEGIN.*PRIVATE KEY"; then
  echo "  ✗ File does not look like a PEM private key."
  exit 1
fi
echo "  ✓ PEM file is valid."

# ─────────────────────────────────────────────────────────────────────────────
# 2. Authenticate with Managed Identity
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "▸ Step 2: Authenticating with Managed Identity..."
az login --identity --output none 2>/dev/null || {
  echo "  ⚠ Managed Identity not available, using current session..."
}
echo "  ✓ Authenticated as: $(az account show --query user.name -o tsv)"

# ─────────────────────────────────────────────────────────────────────────────
# 3. Upload PEM to Key Vault
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "▸ Step 3: Uploading PEM to Key Vault..."
az keyvault secret set \
  --vault-name "${KEY_VAULT_NAME}" \
  --name "${SECRET_NAME}" \
  --file "${PEM_FILE}" \
  --content-type "application/x-pem-file" \
  --output none

echo "  ✓ PEM uploaded to ${KEY_VAULT_NAME}/${SECRET_NAME}"

# ─────────────────────────────────────────────────────────────────────────────
# 4. Verify secret is readable
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "▸ Step 4: Verifying secret..."
RETRIEVED=$(az keyvault secret show \
  --vault-name "${KEY_VAULT_NAME}" \
  --name "${SECRET_NAME}" \
  --query "value" -o tsv | head -1)

if echo "${RETRIEVED}" | grep -q "BEGIN"; then
  echo "  ✓ Secret is readable and looks like a valid PEM."
else
  echo "  ✗ Secret retrieved but doesn't look like PEM."
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# 5. Test GitHub App JWT generation
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "▸ Step 5: Testing JWT generation..."
JWT=$(node --input-type=module -e "
  import { generateAppJwt } from './lib/github-app-auth.mjs';
  import { getKeyVaultSecret } from './lib/azure-identity.mjs';
  const pem = await getKeyVaultSecret('${KEY_VAULT_NAME}', '${SECRET_NAME}');
  const jwt = generateAppJwt('${GITHUB_APP_ID}', pem);
  process.stdout.write(jwt);
" 2>/dev/null) || {
  echo "  ⚠ JWT generation via IMDS failed (expected if not on Azure VM)."
  echo "  Trying with local PEM file..."
  JWT=$(node --input-type=module -e "
    import { readFileSync } from 'node:fs';
    import { generateAppJwt } from './lib/github-app-auth.mjs';
    const pem = readFileSync('${PEM_FILE}', 'utf8');
    const jwt = generateAppJwt('${GITHUB_APP_ID}', pem);
    process.stdout.write(jwt);
  ")
}

echo "  ✓ JWT generated (${#JWT} chars)"

# ─────────────────────────────────────────────────────────────────────────────
# 6. Verify with GitHub API
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "▸ Step 6: Verifying with GitHub API..."
APP_INFO=$(curl -sf \
  -H "Authorization: Bearer ${JWT}" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/app")

APP_NAME=$(echo "${APP_INFO}" | python3 -c "import sys,json; print(json.load(sys.stdin)['name'])")
APP_SLUG=$(echo "${APP_INFO}" | python3 -c "import sys,json; print(json.load(sys.stdin)['slug'])")
echo "  ✓ Authenticated as GitHub App: ${APP_NAME} (${APP_SLUG})"

# ─────────────────────────────────────────────────────────────────────────────
# 7. Get installation token
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "▸ Step 7: Getting installation token..."
TOKEN_RESPONSE=$(curl -sf \
  -X POST \
  -H "Authorization: Bearer ${JWT}" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/app/installations/${GITHUB_INSTALLATION_ID}/access_tokens")

EXPIRES=$(echo "${TOKEN_RESPONSE}" | python3 -c "import sys,json; print(json.load(sys.stdin)['expires_at'])")
echo "  ✓ Installation token obtained (expires: ${EXPIRES})"

# ─────────────────────────────────────────────────────────────────────────────
# 8. Clean up PEM file
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "▸ Step 8: Cleaning up..."
echo "  ⚠ IMPORTANT: Delete the PEM file from this VM now:"
echo "    rm -f ${PEM_FILE}"
echo "  The PEM is safely stored in Key Vault and should NOT remain on disk."

# ─────────────────────────────────────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  ✓ GitHub App Setup Complete                                    ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║  App: ${APP_NAME} (ID: ${GITHUB_APP_ID})                       "
echo "║  PEM: ${KEY_VAULT_NAME}/${SECRET_NAME}                         "
echo "║  Token flow: UAMI → Key Vault → JWT → Installation Token      ║"
echo "║                                                                 ║"
echo "║  Add to OpenClaw config:                                        ║"
echo "║    GITHUB_APP_ID=${GITHUB_APP_ID}                               "
echo "║    GITHUB_INSTALLATION_ID=${GITHUB_INSTALLATION_ID}             "
echo "║    KEY_VAULT_NAME=${KEY_VAULT_NAME}                             "
echo "╚══════════════════════════════════════════════════════════════════╝"
