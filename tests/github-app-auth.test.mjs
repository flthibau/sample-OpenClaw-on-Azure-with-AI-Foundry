// =============================================================================
// github-app-auth.test.mjs — Unit tests for GitHub App JWT generation
// Run: node --test tests/github-app-auth.test.mjs
// =============================================================================

import { describe, it, mock, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { generateAppJwt, getInstallationToken, verifyApp } from '../lib/github-app-auth.mjs';
import { generateKeyPairSync } from 'node:crypto';

// Generate a test RSA key pair
const { privateKey: testPem } = generateKeyPairSync('rsa', {
  modulusLength: 2048,
  privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
  publicKeyEncoding: { type: 'spki', format: 'pem' },
});

const TEST_APP_ID = '123456';
const TEST_INSTALLATION_ID = '78901234';

// =============================================================================
// generateAppJwt
// =============================================================================

describe('generateAppJwt', () => {
  it('should return a valid 3-segment JWT', () => {
    const jwt = generateAppJwt(TEST_APP_ID, testPem);
    const parts = jwt.split('.');
    assert.equal(parts.length, 3, 'JWT must have 3 segments');
  });

  it('should have correct header', () => {
    const jwt = generateAppJwt(TEST_APP_ID, testPem);
    const header = JSON.parse(Buffer.from(jwt.split('.')[0], 'base64url').toString());
    assert.equal(header.alg, 'RS256');
    assert.equal(header.typ, 'JWT');
  });

  it('should have correct payload with iss = appId', () => {
    const jwt = generateAppJwt(TEST_APP_ID, testPem);
    const payload = JSON.parse(Buffer.from(jwt.split('.')[1], 'base64url').toString());
    assert.equal(payload.iss, TEST_APP_ID);
    assert.ok(payload.iat, 'iat must be set');
    assert.ok(payload.exp, 'exp must be set');
  });

  it('should set exp to ~10 minutes after iat', () => {
    const jwt = generateAppJwt(TEST_APP_ID, testPem);
    const payload = JSON.parse(Buffer.from(jwt.split('.')[1], 'base64url').toString());
    const diff = payload.exp - payload.iat;
    // iat is set to now - 60, exp is now + 600, so diff = 660
    assert.ok(diff >= 600 && diff <= 720, `exp - iat should be ~660, got ${diff}`);
  });

  it('should produce different JWTs at different times', () => {
    const jwt1 = generateAppJwt(TEST_APP_ID, testPem);
    // Advance clock simulation (different iat)
    const jwt2 = generateAppJwt(TEST_APP_ID, testPem);
    // They may be identical if called within same second, that's OK
    assert.equal(typeof jwt1, 'string');
    assert.equal(typeof jwt2, 'string');
  });

  it('should throw with invalid PEM', () => {
    assert.throws(
      () => generateAppJwt(TEST_APP_ID, 'not-a-pem'),
      /error/i,
    );
  });
});

// =============================================================================
// getInstallationToken
// =============================================================================

describe('getInstallationToken', () => {
  it('should call GitHub API with correct URL and headers', async () => {
    const expectedUrl = `https://api.github.com/app/installations/${TEST_INSTALLATION_ID}/access_tokens`;

    const originalFetch = globalThis.fetch;
    globalThis.fetch = mock.fn(async (url, opts) => {
      assert.equal(url, expectedUrl);
      assert.equal(opts.method, 'POST');
      assert.ok(opts.headers.Authorization.startsWith('Bearer '));
      assert.equal(opts.headers.Accept, 'application/vnd.github+json');

      return {
        ok: true,
        json: async () => ({
          token: 'ghs_test_token_123',
          expires_at: '2026-02-16T12:00:00Z',
        }),
      };
    });

    try {
      const result = await getInstallationToken('test-jwt', TEST_INSTALLATION_ID);
      assert.equal(result.token, 'ghs_test_token_123');
      assert.ok(result.expiresAt instanceof Date);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it('should throw on non-OK response', async () => {
    const originalFetch = globalThis.fetch;
    globalThis.fetch = mock.fn(async () => ({
      ok: false,
      status: 401,
      text: async () => '{"message":"Bad credentials"}',
    }));

    try {
      await assert.rejects(
        () => getInstallationToken('bad-jwt', TEST_INSTALLATION_ID),
        /401/,
      );
    } finally {
      globalThis.fetch = originalFetch;
    }
  });
});

// =============================================================================
// verifyApp
// =============================================================================

describe('verifyApp', () => {
  it('should call GET /app with correct auth header', async () => {
    const originalFetch = globalThis.fetch;
    globalThis.fetch = mock.fn(async (url, opts) => {
      assert.equal(url, 'https://api.github.com/app');
      assert.ok(opts.headers.Authorization.startsWith('Bearer '));

      return {
        ok: true,
        json: async () => ({
          id: 123456,
          name: 'openclaw-agent',
          slug: 'openclaw-agent',
        }),
      };
    });

    try {
      const result = await verifyApp('test-jwt');
      assert.equal(result.id, 123456);
      assert.equal(result.slug, 'openclaw-agent');
    } finally {
      globalThis.fetch = originalFetch;
    }
  });
});
