// =============================================================================
// azure-identity.test.mjs — Unit tests for Azure UAMI + Key Vault
// Run: node --test tests/azure-identity.test.mjs
// =============================================================================

import { describe, it, mock } from 'node:test';
import assert from 'node:assert/strict';
import {
  getManagedIdentityToken,
  getKeyVaultSecret,
  getArmToken,
  getCognitiveServicesToken,
  getStorageToken,
} from '../lib/azure-identity.mjs';

const MOCK_TOKEN = 'eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.mock';
const MOCK_EXPIRES_ON = String(Math.floor(Date.now() / 1000) + 3600);

// =============================================================================
// getManagedIdentityToken
// =============================================================================

describe('getManagedIdentityToken', () => {
  it('should call IMDS endpoint with correct parameters', async () => {
    const originalFetch = globalThis.fetch;
    globalThis.fetch = mock.fn(async (url, opts) => {
      assert.ok(url.startsWith('http://169.254.169.254/metadata/identity/oauth2/token'));
      assert.ok(url.includes('api-version=2018-02-01'));
      assert.ok(url.includes('resource=https%3A%2F%2Fvault.azure.net'));
      assert.equal(opts.headers.Metadata, 'true');

      return {
        ok: true,
        json: async () => ({
          access_token: MOCK_TOKEN,
          expires_on: MOCK_EXPIRES_ON,
          resource: 'https://vault.azure.net',
          token_type: 'Bearer',
        }),
      };
    });

    try {
      const result = await getManagedIdentityToken('https://vault.azure.net');
      assert.equal(result.accessToken, MOCK_TOKEN);
      assert.ok(result.expiresOn instanceof Date);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it('should include client_id for UAMI when provided', async () => {
    const testClientId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    const originalFetch = globalThis.fetch;
    globalThis.fetch = mock.fn(async (url) => {
      assert.ok(url.includes(`client_id=${testClientId}`));
      return {
        ok: true,
        json: async () => ({
          access_token: MOCK_TOKEN,
          expires_on: MOCK_EXPIRES_ON,
        }),
      };
    });

    try {
      await getManagedIdentityToken('https://vault.azure.net', testClientId);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it('should throw on IMDS failure', async () => {
    const originalFetch = globalThis.fetch;
    globalThis.fetch = mock.fn(async () => ({
      ok: false,
      status: 400,
      text: async () => 'identity not found',
    }));

    try {
      await assert.rejects(
        () => getManagedIdentityToken('https://vault.azure.net'),
        /400/,
      );
    } finally {
      globalThis.fetch = originalFetch;
    }
  });
});

// =============================================================================
// getKeyVaultSecret
// =============================================================================

describe('getKeyVaultSecret', () => {
  it('should fetch token then fetch secret', async () => {
    let callCount = 0;
    const originalFetch = globalThis.fetch;
    globalThis.fetch = mock.fn(async (url) => {
      callCount++;
      if (url.includes('169.254.169.254')) {
        // IMDS call
        return {
          ok: true,
          json: async () => ({
            access_token: MOCK_TOKEN,
            expires_on: MOCK_EXPIRES_ON,
          }),
        };
      }
      if (url.includes('vault.azure.net')) {
        // Key Vault call
        assert.ok(url.includes('kv-test.vault.azure.net/secrets/my-secret'));
        return {
          ok: true,
          json: async () => ({
            value: '-----BEGIN RSA PRIVATE KEY-----\ntest\n-----END RSA PRIVATE KEY-----',
            id: 'https://kv-test.vault.azure.net/secrets/my-secret/version1',
          }),
        };
      }
      throw new Error(`Unexpected URL: ${url}`);
    });

    try {
      const secret = await getKeyVaultSecret('kv-test', 'my-secret');
      assert.ok(secret.includes('BEGIN RSA PRIVATE KEY'));
      assert.equal(callCount, 2, 'Should make 2 calls: IMDS + Key Vault');
    } finally {
      globalThis.fetch = originalFetch;
    }
  });
});

// =============================================================================
// Convenience functions
// =============================================================================

describe('convenience token functions', () => {
  const mockFetch = mock.fn(async () => ({
    ok: true,
    json: async () => ({
      access_token: MOCK_TOKEN,
      expires_on: MOCK_EXPIRES_ON,
    }),
  }));

  it('getArmToken should request management.azure.com', async () => {
    const originalFetch = globalThis.fetch;
    globalThis.fetch = mock.fn(async (url) => {
      assert.ok(url.includes('management.azure.com'));
      return {
        ok: true,
        json: async () => ({
          access_token: MOCK_TOKEN,
          expires_on: MOCK_EXPIRES_ON,
        }),
      };
    });

    try {
      const result = await getArmToken();
      assert.equal(result.accessToken, MOCK_TOKEN);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it('getCognitiveServicesToken should request cognitiveservices.azure.com', async () => {
    const originalFetch = globalThis.fetch;
    globalThis.fetch = mock.fn(async (url) => {
      assert.ok(url.includes('cognitiveservices.azure.com'));
      return {
        ok: true,
        json: async () => ({
          access_token: MOCK_TOKEN,
          expires_on: MOCK_EXPIRES_ON,
        }),
      };
    });

    try {
      const result = await getCognitiveServicesToken();
      assert.equal(result.accessToken, MOCK_TOKEN);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it('getStorageToken should request storage.azure.com', async () => {
    const originalFetch = globalThis.fetch;
    globalThis.fetch = mock.fn(async (url) => {
      assert.ok(url.includes('storage.azure.com'));
      return {
        ok: true,
        json: async () => ({
          access_token: MOCK_TOKEN,
          expires_on: MOCK_EXPIRES_ON,
        }),
      };
    });

    try {
      const result = await getStorageToken();
      assert.equal(result.accessToken, MOCK_TOKEN);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });
});
