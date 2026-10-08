'use strict';
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const test = require('node:test');

// Written before the new diagnostic. Every Apple response and credential is synthetic.
const modulePromise = import('../scripts/testflight-install-check.mjs');
const origin = 'https://api.appstoreconnect.apple.com';
const appId = '6766271119';
const buildVersion = '202610081128';
const ownerEmail = 'tahar.galai@gmail.com';
const bearer = 'Bearer synthetic-private-credential';
const privateMarker = 'DO-NOT-EMIT-private-person-or-server-error';
const resource = (type, id, attributes, relationships) => ({ type, id, attributes, relationships });
const reply = (data, status = 200) => new Response(JSON.stringify(data), { status });

function fixture(overrides = {}) {
  const calls = [];
  const routes = {
    [`/v1/apps/${appId}`]: { data: resource('apps', appId, { bundleId: 'app.mise.driver' }) },
    '/v1/builds': { data: [resource('builds', 'exact-build', {
      version: buildVersion, processingState: 'VALID', expired: false,
    }, { app: { data: { type: 'apps', id: appId } } })] },
    '/v1/builds/exact-build/buildBetaDetail': { data: resource('buildBetaDetails', 'detail', {
      internalBuildState: 'IN_BETA_TESTING', externalBuildState: 'NOT_APPLICABLE',
    }) },
    '/v1/betaTesters': { data: [resource('betaTesters', 'owner-tester', {
      email: ownerEmail, state: 'ACCEPTED', inviteType: 'EMAIL',
    }), resource('betaTesters', 'unrelated-tester', { email: privateMarker, state: privateMarker })] },
    '/v1/betaTesters/owner-tester/apps': { data: [resource('apps', appId, { bundleId: 'app.mise.driver' })] },
    [`/v1/apps/${appId}/betaGroups`]: { data: [resource('betaGroups', 'all-builds-group', {
      isInternalGroup: true, hasAccessToAllBuilds: true, name: privateMarker,
    })] },
    '/v1/betaGroups/all-builds-group/betaTesters': { data: [
      resource('betaTesters', 'unrelated-tester', { state: privateMarker }),
      resource('betaTesters', 'owner-tester', { state: 'ACCEPTED', inviteType: 'EMAIL' }),
    ] },
    '/v1/betaGroups/all-builds-group/builds': { data: [resource('builds', 'exact-build', { version: buildVersion })] },
    '/v1/users': { data: [resource('users', 'owner-user', {
      username: ownerEmail, roles: ['ADMIN'], allAppsVisible: false,
    }), resource('users', 'unrelated-user', { username: privateMarker, roles: [privateMarker] })] },
    '/v1/users/owner-user/visibleApps': { data: [resource('apps', appId, { bundleId: 'app.mise.driver' })] },
    ...overrides,
  };
  const fetchImpl = async (rawUrl, options) => {
    const url = new URL(rawUrl);
    assert.equal(url.origin, origin);
    assert.equal(options.method, 'GET');
    assert.equal(options.redirect, 'error');
    assert.equal(options.headers.Authorization, bearer);
    assert.ok(options.signal instanceof AbortSignal);
    calls.push({ url, options });
    const data = routes[url.pathname];
    assert.ok(data, 'Unexpected fixture route');
    return typeof data === 'function' ? data(url, options) : reply(data);
  };
  return { fetchImpl, calls };
}

async function check(overrides, readerOptions = {}) {
  const api = await modulePromise;
  const mock = fixture(overrides);
  const report = await api.runInstallCheck(api.createReader({
    fetchImpl: mock.fetchImpl, authorization: bearer, ...readerOptions,
  }));
  return { report, ...mock };
}

test('reports only the exact app/build and owner access, including the current all-builds group', async () => {
  const { report, calls } = await check();
  assert.equal(report.complete, true);
  assert.deepEqual(report.app, { identityMatches: true });
  assert.equal(report.build.exactMatch, true);
  assert.equal(report.build.processingState, 'VALID');
  assert.equal(report.build.expired, false);
  assert.equal(report.build.internalBuildState, 'IN_BETA_TESTING');
  assert.equal(report.owner.tester.exists, true);
  assert.equal(report.owner.tester.state, 'ACCEPTED');
  assert.equal(report.owner.tester.inviteType, 'EMAIL');
  assert.equal(report.owner.tester.appMember, true);
  assert.equal(report.owner.tester.appGroupMember, true);
  assert.equal(report.owner.tester.internalAllBuildsGroupMember, true);
  assert.equal(report.owner.tester.exactBuildInMemberGroup, true);
  assert.equal(report.owner.appStoreUser.appAccess, true);
  assert.deepEqual(report.owner.appStoreUser.roles, ['ADMIN']);
  assert.equal(report.physicalInstallationVerified, false);
  const serialized = JSON.stringify(report);
  for (const secret of [ownerEmail, privateMarker, bearer, 'owner-tester', 'owner-user', 'all-builds-group']) {
    assert.equal(serialized.includes(secret), false);
  }
  const testers = calls.find(call => call.url.pathname === '/v1/betaTesters').url;
  assert.equal(testers.searchParams.get('filter[email]'), ownerEmail);
  assert.equal(testers.searchParams.get('fields[betaTesters]'), 'email,state,inviteType');
  const builds = calls.find(call => call.url.pathname === '/v1/builds').url;
  assert.equal(builds.searchParams.get('filter[app]'), appId);
  assert.equal(builds.searchParams.get('filter[version]'), buildVersion);
  assert.equal(builds.searchParams.get('include'), 'app', 'Request app linkage explicitly');
  const users = calls.find(call => call.url.pathname === '/v1/users').url;
  assert.equal(users.searchParams.get('filter[username]'), ownerEmail);
  const members = calls.find(call => call.url.pathname.endsWith('/all-builds-group/betaTesters')).url;
  assert.equal(members.searchParams.has('filter[email]'), false, 'Apple does not support this group-member filter');
  assert.equal(members.searchParams.get('fields[betaTesters]'), 'state,inviteType');
});

test('missing owner cannot be substituted by another tester/user or trigger other-user requests', async () => {
  const { report, calls } = await check({
    '/v1/betaTesters': { data: [resource('betaTesters', 'unrelated-tester', { email: privateMarker })] },
    '/v1/users': { data: [] },
  });
  assert.equal(report.owner.tester.exists, false);
  assert.equal(report.owner.appStoreUser.exists, false);
  assert.equal(report.owner.tester.appMember, false);
  assert.equal(report.owner.tester.internalAllBuildsGroupMember, false);
  assert.equal(report.owner.tester.matchedRecords, 0);
  assert.equal(report.owner.tester.uniqueProfiles, 0);
  assert.equal(report.owner.tester.repeatedRecords, 0);
  assert.equal(report.owner.tester.multipleProfiles, false);
  assert.deepEqual(report.owner.tester.profiles, []);
  assert.equal(calls.some(call => call.url.pathname.includes('unrelated-tester')), false);
});

const ownProfile = (id, state = 'ACCEPTED', inviteType = 'EMAIL') =>
  resource('betaTesters', id, { email: ownerEmail, state, inviteType });
const twoProfiles = () => [ownProfile('owner-tester'), ownProfile('second-owned-profile', 'INVITED', 'PUBLIC_LINK')];

test('distinct own profiles are individually traced without selecting one or repeating group reads', async () => {
  const { report, calls } = await check({
    '/v1/betaTesters': { data: twoProfiles() },
    '/v1/betaTesters/second-owned-profile/apps': { data: [] },
  });
  const tester = report.owner.tester;
  assert.equal(report.complete, true);
  assert.equal(tester.matchedRecords, 2);
  assert.equal(tester.uniqueProfiles, 2);
  assert.equal(tester.repeatedRecords, 0);
  assert.equal(tester.multipleProfiles, true);
  assert.equal(tester.aggregation, 'ANY_PROFILE');
  assert.equal(tester.state, 'UNKNOWN');
  assert.equal(tester.inviteType, 'UNKNOWN');
  assert.deepEqual(tester.profiles, [
    { ordinal: 1, state: 'ACCEPTED', inviteType: 'EMAIL', appMember: true,
      appGroupMember: true, internalAllBuildsGroupMember: true, exactBuildInMemberGroup: true },
    { ordinal: 2, state: 'INVITED', inviteType: 'PUBLIC_LINK', appMember: false,
      appGroupMember: false, internalAllBuildsGroupMember: false, exactBuildInMemberGroup: false },
  ]);
  assert.equal(tester.appMember, true);
  assert.equal(tester.internalAllBuildsGroupMember, true);
  assert.equal(calls.filter(call => call.url.pathname === '/v1/betaGroups/all-builds-group/betaTesters').length, 1);
  assert.equal(calls.filter(call => call.url.pathname === '/v1/betaGroups/all-builds-group/builds').length, 1);
  for (const value of [ownerEmail, 'owner-tester', 'second-owned-profile', bearer, privateMarker]) {
    assert.equal(JSON.stringify(report).includes(value), false);
  }
});

test('same own ID repeated across pagination is counted but traced once', async () => {
  const { report, calls } = await check({ '/v1/betaTesters': url => {
    if (url.searchParams.has('cursor')) return reply({ data: [ownProfile('owner-tester'),
      resource('betaTesters', 'unrelated-tester', { email: privateMarker })] });
    const next = new URL(url); next.searchParams.set('cursor', 'overlap');
    return reply({ data: [ownProfile('owner-tester')], links: { next: next.href } });
  } });
  const tester = report.owner.tester;
  assert.equal(report.complete, true);
  assert.equal(tester.matchedRecords, 2);
  assert.equal(tester.uniqueProfiles, 1);
  assert.equal(tester.repeatedRecords, 1);
  assert.equal(tester.multipleProfiles, false);
  assert.equal(tester.state, 'ACCEPTED');
  assert.equal(tester.profiles.length, 1);
  assert.equal(calls.filter(call => call.url.pathname === '/v1/betaTesters/owner-tester/apps').length, 1);
});

test('contradictory rows for an own ID fail closed instead of selecting a version', async () => {
  for (const changes of [
    { state: 'INVITED' }, { inviteType: 'PUBLIC_LINK' }, { email: privateMarker },
  ]) {
    const { report, calls } = await check({ '/v1/betaTesters': url => {
      if (url.searchParams.has('cursor')) return reply({ data: [resource('betaTesters', 'owner-tester', {
        email: ownerEmail, state: 'ACCEPTED', inviteType: 'EMAIL', ...changes,
      })] });
      const next = new URL(url); next.searchParams.set('cursor', 'conflict');
      return reply({ data: [ownProfile('owner-tester')], links: { next: next.href } });
    } });
    assert.equal(report.complete, false);
    assert.equal(report.errors.some(error => error.section === 'tester' && error.status === 'CONFLICTING_OWNER_PROFILE'), true);
    assert.equal(report.owner.tester.exists, null);
    assert.deepEqual(report.owner.tester.profiles, []);
    assert.equal(calls.some(call => /\/betaTesters\/[^/]+\/apps$/.test(call.url.pathname)), false);
    assert.equal(JSON.stringify(report).includes(privateMarker), false);
  }
});

test('more than ten distinct own profiles cannot expand follow-up reads', async () => {
  const { report, calls } = await check({ '/v1/betaTesters': {
    data: Array.from({ length: 11 }, (_value, index) => ownProfile(`owned-profile-${index}`)),
  } });
  assert.equal(report.complete, false);
  assert.equal(report.errors.some(error => error.status === 'OWNER_PROFILE_LIMIT'), true);
  assert.equal(report.owner.tester.exists, null);
  assert.deepEqual(report.owner.tester.profiles, []);
  assert.equal(calls.some(call => /\/betaTesters\/[^/]+\/apps$/.test(call.url.pathname)), false);
});

test('one own profile failing with 403 or invalid data cannot erase another profile positive', async () => {
  for (const failedRead of [() => reply({ errors: [{ detail: privateMarker }] }, 403), { data: null }]) {
    const { report } = await check({ '/v1/betaTesters': { data: twoProfiles() },
      '/v1/betaTesters/second-owned-profile/apps': failedRead });
    assert.equal(report.complete, false);
    assert.equal(report.owner.tester.appMember, true);
    assert.equal(report.owner.tester.profiles[0].appMember, true);
    assert.equal(report.owner.tester.profiles[1].appMember, null);
    assert.equal(report.errors.some(error => error.section === 'testerApp' && error.profileOrdinal === 2
      && ['HTTP_FORBIDDEN', 'INVALID_RESPONSE'].includes(error.status)), true);
    assert.equal(JSON.stringify(report).includes(privateMarker), false);
  }
});

test('all unresolved own profiles aggregate to unknown instead of a confirmed negative', async () => {
  const { report } = await check({ '/v1/betaTesters': { data: twoProfiles() },
    '/v1/betaTesters/owner-tester/apps': () => reply({ errors: [{ detail: privateMarker }] }, 403),
    '/v1/betaTesters/second-owned-profile/apps': { data: null },
    '/v1/betaGroups/all-builds-group/betaTesters': () => reply({ errors: [{ detail: privateMarker }] }, 403),
  });
  assert.equal(report.complete, false);
  for (const field of ['appMember', 'appGroupMember', 'internalAllBuildsGroupMember', 'exactBuildInMemberGroup']) {
    assert.equal(report.owner.tester[field], null);
    assert.equal(report.owner.tester.profiles.every(profile => profile[field] === null), true);
  }
});

test('a failed second group preserves proven profile memberships and leaves unresolved negatives unknown', async () => {
  for (const failedRead of [() => reply({ errors: [{ detail: privateMarker }] }, 403), { data: null }]) {
    const { report, calls } = await check({ '/v1/betaTesters': { data: twoProfiles() },
      '/v1/betaTesters/second-owned-profile/apps': { data: [] },
      [`/v1/apps/${appId}/betaGroups`]: { data: [
        resource('betaGroups', 'all-builds-group', { isInternalGroup: true, hasAccessToAllBuilds: true }),
        resource('betaGroups', 'unreadable-group', { isInternalGroup: true, hasAccessToAllBuilds: true }),
      ] },
      '/v1/betaGroups/unreadable-group/betaTesters': failedRead,
    });
    assert.equal(report.complete, false);
    const [first, second] = report.owner.tester.profiles;
    assert.equal(first.appGroupMember, true);
    assert.equal(first.internalAllBuildsGroupMember, true);
    assert.equal(first.exactBuildInMemberGroup, true);
    assert.equal(second.appGroupMember, null);
    assert.equal(second.internalAllBuildsGroupMember, null);
    assert.equal(second.exactBuildInMemberGroup, null);
    assert.equal(report.owner.tester.appGroupMember, true);
    assert.equal(calls.filter(call => call.url.pathname === '/v1/betaGroups/unreadable-group/betaTesters').length, 1);
  }
});

test('group page overlap is memoized for all own profiles without redundant members/build reads', async () => {
  const group = resource('betaGroups', 'all-builds-group', { isInternalGroup: true, hasAccessToAllBuilds: true });
  const { report, calls } = await check({ '/v1/betaTesters': { data: twoProfiles() },
    '/v1/betaTesters/second-owned-profile/apps': { data: [] },
    [`/v1/apps/${appId}/betaGroups`]: { data: [group, group] },
    '/v1/betaGroups/all-builds-group/betaTesters': { data: twoProfiles() },
  });
  assert.equal(report.complete, true);
  assert.equal(report.owner.tester.profiles.every(profile => profile.exactBuildInMemberGroup === true), true);
  assert.equal(calls.filter(call => call.url.pathname === '/v1/betaGroups/all-builds-group/betaTesters').length, 1);
  assert.equal(calls.filter(call => call.url.pathname === '/v1/betaGroups/all-builds-group/builds').length, 1);
});

test('one member group build-read failure leaves that own profile unknown and preserves the other build proof', async () => {
  for (const failedRead of [() => reply({ errors: [{ detail: privateMarker }] }, 403), { data: null }]) {
    const { report, calls } = await check({ '/v1/betaTesters': { data: twoProfiles() },
      '/v1/betaTesters/second-owned-profile/apps': { data: [] },
      [`/v1/apps/${appId}/betaGroups`]: { data: [
        resource('betaGroups', 'all-builds-group', { isInternalGroup: true, hasAccessToAllBuilds: true }),
        resource('betaGroups', 'second-member-group', { isInternalGroup: false, hasAccessToAllBuilds: false }),
      ] },
      '/v1/betaGroups/second-member-group/betaTesters': { data: [twoProfiles()[1]] },
      '/v1/betaGroups/second-member-group/builds': failedRead,
    });
    assert.equal(report.complete, false);
    assert.equal(report.owner.tester.profiles[0].exactBuildInMemberGroup, true);
    assert.equal(report.owner.tester.profiles[1].appGroupMember, true);
    assert.equal(report.owner.tester.profiles[1].exactBuildInMemberGroup, null);
    assert.equal(report.owner.tester.exactBuildInMemberGroup, true);
    assert.equal(calls.filter(call => call.url.pathname === '/v1/betaGroups/second-member-group/builds').length, 1);
    assert.equal(JSON.stringify(report).includes(privateMarker), false);
  }
});

test('unexpected App Store user ambiguity remains fail-closed', async () => {
  const { report, calls } = await check({ '/v1/users': { data: [
    resource('users', 'owner-user', { username: ownerEmail, roles: ['ADMIN'], allAppsVisible: true }),
    resource('users', 'second-user', { username: ownerEmail, roles: ['DEVELOPER'], allAppsVisible: true }),
  ] } });
  assert.equal(report.complete, false);
  assert.equal(report.owner.appStoreUser.exists, null);
  assert.equal(report.owner.appStoreUser.appAccess, null);
  assert.equal(report.errors.some(error => error.section === 'appStoreUser' && error.status === 'AMBIGUOUS_OWNER'), true);
  assert.equal(calls.some(call => call.url.pathname.includes('second-user')), false);
});

test('app identity mismatch stops identity-dependent checks', async () => {
  const { report, calls } = await check({
    [`/v1/apps/${appId}`]: { data: resource('apps', appId, { bundleId: 'foreign.bundle' }) },
  });
  assert.equal(report.app.identityMatches, false);
  assert.equal(report.complete, false);
  assert.equal(calls.length, 1);
});

test('wrong build version, app relationship or type cannot satisfy the exact-build check', async () => {
  for (const build of [
    resource('builds', 'other', { version: '202610071234' }, { app: { data: { type: 'apps', id: appId } } }),
    resource('builds', 'other', { version: buildVersion }, { app: { data: { type: 'apps', id: 'foreign-app' } } }),
    resource('betaGroups', 'other', { version: buildVersion }, { app: { data: { type: 'apps', id: appId } } }),
  ]) {
    const { report, calls } = await check({ '/v1/builds': { data: [build] } });
    assert.equal(report.build.exactMatch, false);
    assert.equal(calls.some(call => call.url.pathname.includes('/other/')), false);
  }
});

test('expired, processing and unrecognized server statuses remain explicit without leaking arbitrary strings', async () => {
  const { report } = await check({
    '/v1/builds': { data: [resource('builds', 'exact-build', {
      version: buildVersion, processingState: 'PROCESSING', expired: true,
    }, { app: { data: { type: 'apps', id: appId } } })] },
    '/v1/builds/exact-build/buildBetaDetail': { data: resource('buildBetaDetails', 'detail', {
      internalBuildState: privateMarker, externalBuildState: 'WAITING_FOR_BETA_REVIEW',
    }) },
  });
  assert.equal(report.build.expired, true);
  assert.equal(report.build.processingState, 'PROCESSING');
  assert.equal(report.build.internalBuildState, 'UNKNOWN');
  assert.equal(report.build.externalBuildState, 'WAITING_FOR_BETA_REVIEW');
  assert.equal(JSON.stringify(report).includes(privateMarker), false);
});

test('owner without all-builds membership is distinguished from a group that exists', async () => {
  const { report } = await check({
    '/v1/betaGroups/all-builds-group/betaTesters': { data: [resource('betaTesters', 'unrelated-tester', {})] },
  });
  assert.equal(report.groups.internalAllBuildsGroupExists, true);
  assert.equal(report.owner.tester.appGroupMember, false);
  assert.equal(report.owner.tester.internalAllBuildsGroupMember, false);
  assert.equal(report.owner.tester.exactBuildInMemberGroup, false);
});

test('allAppsVisible avoids an unnecessary visibleApps request', async () => {
  const { report, calls } = await check({ '/v1/users': { data: [resource('users', 'owner-user', {
    username: ownerEmail, roles: ['DEVELOPER', privateMarker], allAppsVisible: true,
  })] } });
  assert.equal(report.owner.appStoreUser.appAccess, true);
  assert.deepEqual(report.owner.appStoreUser.roles, ['DEVELOPER']);
  assert.equal(calls.some(call => call.url.pathname.endsWith('/visibleApps')), false);
});

test('403 for user permissions is unknown, with no private body or error message exposed', async () => {
  let bodyRead = false;
  const { report } = await check({ '/v1/users': () => ({ ok: false, status: 403,
    body: { cancel: async () => {} }, text: async () => { bodyRead = true; return privateMarker; },
  }) });
  assert.equal(report.complete, false);
  assert.equal(report.owner.appStoreUser.exists, null);
  assert.equal(report.owner.appStoreUser.appAccess, null);
  assert.equal(report.errors.some(error => error.section === 'appStoreUser' && error.status === 'HTTP_FORBIDDEN'), true);
  assert.equal(bodyRead, false);
  assert.equal(JSON.stringify(report).includes(privateMarker), false);
});

test('pagination keeps owner filters and fields while following a later owner result', async () => {
  const { report, calls } = await check({ '/v1/betaTesters': url => {
    if (url.searchParams.has('cursor')) return reply({ data: [resource('betaTesters', 'owner-tester', {
      email: ownerEmail, state: 'ACCEPTED', inviteType: 'EMAIL',
    })] });
    const next = new URL(url); next.searchParams.set('cursor', 'next');
    return reply({ data: [], links: { next: next.href } });
  } });
  assert.equal(report.owner.tester.exists, true);
  assert.equal(calls.filter(call => call.url.pathname === '/v1/betaTesters').length, 2);
});

test('hostile pagination cannot change origin, path, scope, fields, limit, or add a mutation hint', async () => {
  const api = await modulePromise;
  const start = `${origin}/v1/betaTesters?filter%5Bemail%5D=${encodeURIComponent(ownerEmail)}&fields%5BbetaTesters%5D=state&limit=20`;
  const variants = [
    'https://evil.example/v1/betaTesters', `${origin}/v1/users`,
    start.replace(encodeURIComponent(ownerEmail), 'other%40example.com'),
    start.replace('=state', '=email'), start.replace('limit=20', 'limit=200'),
    `${start}&method=POST`, `${start}#private`, start.replace('https://', 'https://user:pass@'),
  ];
  for (const next of variants) {
    let requests = 0;
    const reader = api.createReader({ authorization: bearer, fetchImpl: async () => {
      requests++; return reply({ data: [], links: { next } });
    } });
    await assert.rejects(reader.list(start), error => error.code === 'UNSAFE_PAGINATION');
    assert.equal(requests, 1);
  }
});

test('reader rejects non-GET requests, cycles, page/request limits, and malformed responses', async () => {
  const api = await modulePromise;
  let calls = 0;
  const reader = api.createReader({ authorization: bearer, fetchImpl: async () => { calls++; return reply({ data: [] }); } });
  await assert.rejects(reader.get(`${origin}/v1/users`, { method: 'POST' }), error => error.code === 'READ_ONLY_REQUIRED');
  assert.equal(calls, 0);
  const start = `${origin}/v1/users?limit=20`;
  for (const [options, expected] of [
    [{ fetchImpl: async () => reply({ data: [], links: { next: start } }) }, 'PAGINATION_CYCLE'],
    [{ maxPages: 1, fetchImpl: async () => reply({ data: [], links: { next: `${start}&cursor=next` } }) }, 'PAGE_LIMIT'],
    [{ maxRequests: 1, fetchImpl: async () => reply({ data: [], links: { next: `${start}&cursor=next` } }) }, 'REQUEST_LIMIT'],
    [{ fetchImpl: async () => reply({ data: null }) }, 'INVALID_RESPONSE'],
  ]) {
    await assert.rejects(api.createReader({ authorization: bearer, ...options }).list(start), error => error.code === expected);
  }
});

test('network, malformed JSON, oversized bodies and deadlines produce only safe errors', async () => {
  const api = await modulePromise;
  const url = `${origin}/v1/users`;
  for (const [options, code] of [
    [{ fetchImpl: async () => { throw new Error(`${bearer} ${privateMarker}`); } }, 'NETWORK_ERROR'],
    [{ fetchImpl: async () => new Response(privateMarker) }, 'INVALID_RESPONSE'],
    [{ maxBytes: 16, fetchImpl: async () => reply({ data: privateMarker }) }, 'RESPONSE_TOO_LARGE'],
    [{ timeoutMs: 5, fetchImpl: async (_url, { signal }) => new Promise((_resolve, reject) => {
      signal.addEventListener('abort', () => reject(new Error(privateMarker)), { once: true });
    }) }, 'TIMEOUT'],
  ]) {
    await assert.rejects(api.createReader({ authorization: bearer, ...options }).get(url), error => {
      assert.equal(error.message.includes(privateMarker), false);
      assert.equal(error.message.includes(bearer), false);
      return error.code === code;
    });
  }
});

test('workflow is manual-only, read-only and persists only the safe JSON artifact', async () => {
  const workflow = readFileSync(path.join(__dirname, '../.github/workflows/testflight-install-check.yml'), 'utf8');
  assert.match(workflow, /workflow_dispatch:/);
  assert.doesNotMatch(workflow, /\n\s+(push|pull_request|schedule|workflow_run):/);
  assert.match(workflow, /contents: read/);
  assert.match(workflow, /secrets\.APP_STORE_CONNECT_KEY_ID/);
  assert.match(workflow, /secrets\.APP_STORE_CONNECT_ISSUER_ID/);
  assert.match(workflow, /secrets\.APP_STORE_CONNECT_KEY_P8_BASE64/);
  assert.match(workflow, /node --test ios-contract-tests\/TestFlightInstallCheckTests\.cjs/);
  assert.match(workflow, /path: \$\{\{ runner\.temp \}\}\/testflight-install-check\.json/);
  assert.doesNotMatch(workflow, /npm |base64 --decode|private_keys|curl |altool|xcodebuild/);
});
