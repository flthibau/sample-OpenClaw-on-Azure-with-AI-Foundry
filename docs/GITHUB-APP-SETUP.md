# GitHub App Setup Guide for OpenClaw

## 1. Create the GitHub App

1. Go to **https://github.com/settings/apps/new** (user) or **https://github.com/organizations/{org}/settings/apps/new** (org)

2. Fill in:

| Field | Value |
|---|---|
| **App name** | `openclaw-agent` |
| **Homepage URL** | `https://github.com/flthibau/openclaw` |
| **Webhook** | ❌ Deactivate (uncheck "Active") |

3. Set **permissions**:

| Permission | Access | Purpose |
|---|---|---|
| **Repository: Contents** | Read & Write | Clone repos, push code |
| **Repository: Pull requests** | Read & Write | Create/merge PRs |
| **Repository: Metadata** | Read-only | List repos, branches |
| **Repository: Issues** | Read & Write | Create/manage issues |
| **Repository: Actions** | Read-only | Check workflow status |

4. **Where can this GitHub App be installed?** → "Only on this account"

5. Click **Create GitHub App**

6. Note the **App ID** (displayed at the top of the app settings page)

## 2. Generate Private Key

1. On the app settings page, scroll to **Private keys**
2. Click **Generate a private key**
3. A `.pem` file will be downloaded — this is the ONLY copy
4. **Do NOT commit this file or leave it on the VM permanently**

## 3. Install the App

1. Go to the app settings page → **Install App** (left sidebar)
2. Click **Install** next to your account/org
3. Choose:
   - **All repositories** (recommended for OpenClaw)
   - Or **Only select repositories** → pick `openclaw`, `openclaw-config`
4. Click **Install**
5. Note the **Installation ID** from the URL:
   ```
   https://github.com/settings/installations/{INSTALLATION_ID}
   ```

## 4. Upload PEM to Azure Key Vault

Transfer the PEM file to the VM temporarily, then run:

```bash
# Set environment
export GITHUB_APP_ID="<your-app-id>"
export GITHUB_INSTALLATION_ID="<your-installation-id>"
export KEY_VAULT_NAME="kv-openclaw"

# Upload and verify
bash scripts/setup-github-app.sh /tmp/openclaw-agent.pem

# Delete the PEM file immediately after
rm -f /tmp/openclaw-agent.pem
```

## 5. Configure OpenClaw

Add to your OpenClaw environment or config:

```bash
# These are NOT secrets — they're public identifiers
GITHUB_APP_ID=<your-app-id>
GITHUB_INSTALLATION_ID=<your-installation-id>
KEY_VAULT_NAME=kv-openclaw
KEY_VAULT_SECRET_NAME=github-app-pem
```

## 6. Test the Flow

```bash
# Quick test — get a token and call GitHub API
node --input-type=module -e "
  import { TokenManager } from './lib/token-manager.mjs';
  const tm = new TokenManager({
    githubAppId: process.env.GITHUB_APP_ID,
    githubInstallationId: process.env.GITHUB_INSTALLATION_ID,
    keyVaultName: process.env.KEY_VAULT_NAME,
    keyVaultSecretName: 'github-app-pem',
  });
  const token = await tm.getGitHubToken();
  console.log('Token obtained, length:', token.length);
  console.log('Status:', JSON.stringify(tm.status(), null, 2));
"
```

## 7. Use with `gh` CLI

```bash
# Get token and set it for gh
export GH_TOKEN=$(node --input-type=module -e "
  import { TokenManager } from './lib/token-manager.mjs';
  const tm = new TokenManager({
    githubAppId: process.env.GITHUB_APP_ID,
    githubInstallationId: process.env.GITHUB_INSTALLATION_ID,
    keyVaultName: process.env.KEY_VAULT_NAME,
    keyVaultSecretName: 'github-app-pem',
  });
  process.stdout.write(await tm.getGitHubToken());
")

# Now gh CLI works without any login
gh repo list
gh pr list --repo flthibau/openclaw
```

## 8. Use with Copilot SDK

```javascript
import { TokenManager } from './lib/token-manager.mjs';

const tm = new TokenManager({
  githubAppId: process.env.GITHUB_APP_ID,
  githubInstallationId: process.env.GITHUB_INSTALLATION_ID,
  keyVaultName: 'kv-openclaw',
  keyVaultSecretName: 'github-app-pem',
});

// The Copilot SDK accepts GH_TOKEN env var
process.env.GH_TOKEN = await tm.getGitHubToken();

// Now import and use the Copilot SDK
import { CopilotSDK } from '@github/copilot-sdk';
```

## Security Notes

- The PEM private key **never touches disk** after initial upload
- Installation tokens are **scoped** to the installed repositories only
- Tokens **expire in 1 hour** and are auto-refreshed by `TokenManager`
- The GitHub App has **no webhook** — it's a pure API client
- `TokenManager` keeps everything **in memory only**
