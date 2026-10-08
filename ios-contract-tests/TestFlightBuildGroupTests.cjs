'use strict';
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

// Execute the actual CI step against an in-memory Apple API; no credentials or network.
const workflow = readFileSync(path.join(__dirname, '../.github/workflows/ios-testflight.yml'), 'utf8');
const section = workflow.split('      - name: Exakten Build für interne Tester freigeben\n')[1]
  ?.split('      - name: Build-Artefakt sichern\n')[0];
const script = section?.split("          node - <<'EOF'\n")[1]?.split('\n          EOF')[0];
assert.ok(script, 'The actual TestFlight release step must be tested');

const origin = 'https://api.appstoreconnect.apple.com';
const buildId = 'exact-apple-build-id';
const groupId = 'selected-internal-group';
const version = '202610041251';
const linkagePath = `/v1/betaGroups/${groupId}/relationships/builds`;
const linkage = { type: 'builds', id: buildId };

async function release({ groupPage = () => ({ data: [linkage] }), allBuilds = false,
                         testingState = 'IN_BETA_TESTING', requests = [] } = {}) {
  const errors = [];
  const response = (status, body) => ({ ok: status >= 200 && status < 300, status,
    text: async () => body === undefined ? '' : JSON.stringify(body) });
  return vm.runInNewContext(script, {
    Buffer, URL, setTimeout: callback => callback(),
    require: name => {
      assert.equal(name, 'crypto');
      return { createSign: () => ({ update() {}, sign: () => 'synthetic-signature' }) };
    },
    process: {
      env: { KEY_P8_B64: Buffer.from('synthetic-key').toString('base64'), KEY_ID: 'test-key',
        ISSUER_ID: 'test-issuer', APP_ID: 'test-app', BUILD_NO: version },
      exit: code => { throw new Error(`CI exit ${code}: ${errors.join('; ')}`); },
    },
    console: { log() {}, error: error => errors.push(String(error)) },
    fetch: async (url, options) => {
      const parsed = new URL(url);
      assert.equal(parsed.origin, origin, 'Never send the Apple bearer token to another origin');
      const method = options.method;
      requests.push({ path: parsed.pathname + parsed.search, method });
      if (method === 'GET' && parsed.pathname === '/v1/builds') {
        assert.equal(parsed.searchParams.get('filter[app]'), 'test-app');
        assert.equal(parsed.searchParams.get('filter[version]'), version);
        return response(200, { data: [{ id: buildId, type: 'builds', attributes: {
          version, processingState: 'VALID', usesNonExemptEncryption: false,
        } }] });
      }
      if (method === 'GET' && parsed.pathname === '/v1/betaGroups') {
        return response(200, { data: [{ id: groupId, attributes: {
          isInternalGroup: true, hasAccessToAllBuilds: allBuilds, name: 'Synthetic test group',
        } }] });
      }
      if (method === 'POST' && parsed.pathname === linkagePath) {
        assert.deepEqual(JSON.parse(options.body), { data: [linkage] });
        return response(204);
      }
      if (method === 'GET' && parsed.pathname === `/v1/builds/${buildId}/buildBetaDetail`) {
        return response(200, { data: { attributes: { internalBuildState: testingState } } });
      }
      if (method === 'GET' && parsed.pathname === linkagePath) {
        return response(200, groupPage(parsed));
      }
      // Reproduce Apple's actual failure for the former build -> betaGroups GET.
      return response(403, { errors: [{ code: 'FORBIDDEN_ERROR',
        detail: "The relationship 'betaGroups' does not allow 'GET_RELATED'. Allowed operations are: CREATE, DELETE." }] });
    },
  });
}

test('verifies the exact uploaded build from the selected group after successful assignment', async () => {
  const requests = [];
  await release({ requests });
  assert.ok(requests.some(request => request.method === 'POST' && request.path === linkagePath));
  assert.ok(requests.some(request => request.method === 'GET' && request.path === `${linkagePath}?limit=200`));
  assert.equal(requests.some(request => request.path.includes(`/builds/${buildId}/betaGroups`)), false);
});

test('unrelated build IDs or resource types cannot satisfy the assignment gate', async () => {
  await assert.rejects(release({ groupPage: () => ({ data: [
    { type: 'builds', id: 'different-build' }, { type: 'betaGroups', id: buildId },
  ] }) }), /noch nicht für interne Tests bereit/);
});

test('finds the exact build on a later group-linkage page', async () => {
  const requests = [];
  await release({ requests, groupPage: url => url.searchParams.has('cursor')
    ? { data: [linkage] }
    : { data: [], links: { next: `${origin}${linkagePath}?cursor=next&limit=200` } } });
  assert.equal(requests.filter(request => request.method === 'GET' && request.path.startsWith(linkagePath)).length, 2);
});

test('rejects pagination outside the selected Apple group', async () => {
  for (const next of ['https://unexpected.example/builds', `${origin}/v1/betaGroups/other/relationships/builds`]) {
    await assert.rejects(release({ groupPage: () => ({ data: [], links: { next } }) }), /Unexpected beta-group pagination URL/);
  }
});

test('rejects a pagination cycle instead of looping indefinitely', async () => {
  await assert.rejects(release({ groupPage: () => ({ data: [],
    links: { next: `${origin}${linkagePath}?limit=200` } }) }), /Invalid beta-group pagination/);
});

test('rejects malformed linkage responses instead of claiming assignment', async () => {
  await assert.rejects(release({ groupPage: () => ({ data: null }) }), /Invalid beta-group build linkage response/);
});

test('assignment alone does not bypass the Apple beta-state gate', async () => {
  await assert.rejects(release({ testingState: 'FAILED' }), /noch nicht für interne Tests bereit: FAILED/);
});

test('preserves automatic internal groups with access to all builds', async () => {
  const requests = [];
  await release({ allBuilds: true, requests });
  assert.equal(requests.some(request => request.path.startsWith(linkagePath)), false);
});
