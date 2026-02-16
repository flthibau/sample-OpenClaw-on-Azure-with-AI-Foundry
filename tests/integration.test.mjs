// =============================================================================
// integration.test.mjs — End-to-end integration test
// Run ON the Azure VM: node --test tests/integration.test.mjs
// Requires: UAMI attached, Key Vault provisioned, GitHub App installed
// =============================================================================

import { describe, it, before } from 'node:test';
import assert from 'node:assert/strict';
import { TokenManager } from '../lib/token-manager.mjs';

// These must be set as environment variables
const GITHUB_APP_ID = process.env.GITHUB_APP_ID;
const GITHUB_INSTALLATION_ID = process.env.GITHUB_INSTALLATION_ID;
const KEY_VAULT_NAME = process.env.KEY_VAULT_NAME ?? 'kv-openclaw';
const KEY_VAULT_SECRET_NAME = process.env.KEY_VAULT_SECRET_NAME ?? 'github-app-pem';
const UAMI_CLIENT_ID = process.env.UAMI_CLIENT_ID; // optional
const TEST_REPO = process.env.TEST_REPO ?? 'flthibau/openclaw';

const skip = !GITHUB_APP_ID || !GITHUB_INSTALLATION_ID;
const skipMsg = skip ? 'Set GITHUB_APP_ID and GITHUB_INSTALLATION_ID to run' : undefined;

describe('Integration: Full Token Flow', { skip: skipMsg }, () => {
  let tm;

  before(() => {
    tm = new TokenManager({
      githubAppId: GITHUB_APP_ID,
      githubInstallationId: GITHUB_INSTALLATION_ID,
      keyVaultName: KEY_VAULT_NAME,
      keyVaultSecretName: KEY_VAULT_SECRET_NAME,
      uamiClientId: UAMI_CLIENT_ID,
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Azure Credential Tests
  // ─────────────────────────────────────────────────────────────────────────

  it('should acquire Azure ARM token via IMDS', async () => {
    const token = await tm.getArmToken();
    assert.ok(token.length > 100, 'ARM token should be a long JWT');
    assert.ok(token.includes('.'), 'ARM token should contain dots');
  });

  it('should acquire Key Vault token via IMDS', async () => {
    const token = await tm.getKeyVaultToken();
    assert.ok(token.length > 100);
  });

  it('should acquire Cognitive Services token via IMDS', async () => {
    const token = await tm.getCognitiveServicesToken();
    assert.ok(token.length > 100);
  });

  it('should acquire Storage token via IMDS', async () => {
    const token = await tm.getStorageToken();
    assert.ok(token.length > 100);
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Key Vault Access Test
  // ─────────────────────────────────────────────────────────────────────────

  it('should read GitHub App PEM from Key Vault', async () => {
    // This internally uses IMDS → Key Vault
    const token = await tm.getGitHubToken();
    // If we got a GitHub token, it means PEM was read successfully
    assert.ok(token, 'GitHub token should be truthy');
    assert.ok(token.startsWith('ghs_'), 'GitHub token should start with ghs_');
  });

  // ─────────────────────────────────────────────────────────────────────────
  // GitHub Token Tests
  // ─────────────────────────────────────────────────────────────────────────

  it('should get a valid GitHub installation token', async () => {
    const token = await tm.getGitHubToken();
    assert.ok(token.length > 20);

    // Verify token works by calling GitHub API
    const res = await fetch('https://api.github.com/installation/repositories', {
      headers: {
        Authorization: `token ${token}`,
        Accept: 'application/vnd.github+json',
      },
    });
    assert.equal(res.status, 200);

    const data = await res.json();
    assert.ok(data.total_count >= 1, 'Should have at least 1 repo');
  });

  it('should cache and reuse the GitHub token', async () => {
    const token1 = await tm.getGitHubToken();
    const token2 = await tm.getGitHubToken();
    assert.equal(token1, token2, 'Same token should be returned from cache');
  });

  it('should report correct status', () => {
    const status = tm.status();
    assert.ok(status.github.hasToken);
    assert.ok(status.github.pemLoaded);
    assert.ok(status.github.expiresInMs > 0, 'Token should not be expired');
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Git Clone via Installation Token
  // ─────────────────────────────────────────────────────────────────────────

  it('should clone a repo using the installation token', async () => {
    const token = await tm.getGitHubToken();
    const { execSync } = await import('node:child_process');
    const tmpDir = `/tmp/openclaw-integration-test-${Date.now()}`;

    try {
      execSync(
        `git clone --depth=1 https://x-access-token:${token}@github.com/${TEST_REPO}.git ${tmpDir}`,
        { stdio: 'pipe', timeout: 30000 },
      );

      // Verify clone worked
      const { readdirSync } = await import('node:fs');
      const files = readdirSync(tmpDir);
      assert.ok(files.includes('README.md') || files.length > 0, 'Cloned repo should have files');
    } finally {
      execSync(`rm -rf ${tmpDir}`, { stdio: 'pipe' });
    }
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Token Invalidation
  // ─────────────────────────────────────────────────────────────────────────

  it('should re-acquire token after invalidation', async () => {
    const token1 = await tm.getGitHubToken();
    tm.invalidate();

    const status = tm.status();
    assert.ok(!status.github.hasToken, 'Token should be cleared');

    const token2 = await tm.getGitHubToken();
    assert.ok(token2, 'Should get a new token');
    // Token may or may not be different (GitHub can return same token within the hour)
  });
});
