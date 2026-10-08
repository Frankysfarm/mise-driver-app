import { createSign } from 'node:crypto';
import { writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

// Fixed incident scope. This diagnostic never invites, assigns, uploads, or changes access.
const ORIGIN = 'https://api.appstoreconnect.apple.com';
const TARGET = Object.freeze({ app: '6766271119', bundle: 'app.mise.driver',
  build: '202610081128', email: 'tahar.galai@gmail.com' });
const TESTER_STATES = ['NOT_INVITED', 'INVITED', 'ACCEPTED', 'INSTALLED', 'REVOKED'];
const INTERNAL_STATES = ['PROCESSING', 'PROCESSING_EXCEPTION', 'MISSING_EXPORT_COMPLIANCE',
  'READY_FOR_BETA_TESTING', 'IN_BETA_TESTING', 'EXPIRED', 'IN_EXPORT_COMPLIANCE_REVIEW'];
const EXTERNAL_STATES = [...INTERNAL_STATES, 'READY_FOR_BETA_SUBMISSION', 'WAITING_FOR_BETA_REVIEW',
  'IN_BETA_REVIEW', 'BETA_REJECTED', 'BETA_APPROVED', 'NOT_APPLICABLE'];
const ROLES = ['ADMIN', 'FINANCE', 'ACCOUNT_HOLDER', 'SALES', 'MARKETING', 'APP_MANAGER',
  'DEVELOPER', 'ACCESS_TO_REPORTS', 'CUSTOMER_SUPPORT', 'CREATE_APPS',
  'CLOUD_MANAGED_DEVELOPER_ID', 'CLOUD_MANAGED_APP_DISTRIBUTION', 'GENERATE_INDIVIDUAL_KEYS'];
const SAFE_CODES = new Set(['READ_ONLY_REQUIRED', 'UNSAFE_URL', 'UNSAFE_PAGINATION',
  'PAGINATION_CYCLE', 'PAGE_LIMIT', 'REQUEST_LIMIT', 'RESPONSE_TOO_LARGE', 'INVALID_RESPONSE',
  'HTTP_UNAUTHORIZED', 'HTTP_FORBIDDEN', 'HTTP_NOT_FOUND', 'HTTP_RATE_LIMITED', 'HTTP_ERROR',
  'NETWORK_ERROR', 'TIMEOUT', 'AMBIGUOUS_OWNER', 'CONFLICTING_OWNER_PROFILE', 'OWNER_PROFILE_LIMIT', 'APP_IDENTITY_MISMATCH',
  'EXACT_BUILD_NOT_FOUND', 'GROUP_LIMIT', 'CI_REQUIRED', 'CREDENTIALS_UNAVAILABLE',
  'SIGNING_FAILED', 'OUTPUT_FAILED', 'CHECK_FAILED']);

class CheckError extends Error {
  constructor(code) { super(code); this.code = code; }
}
const fail = code => { throw new CheckError(code); };
const safeCode = error => SAFE_CODES.has(error?.code) ? error.code : 'CHECK_FAILED';
const enumValue = (value, values) => values.includes(value) ? value : 'UNKNOWN';
const boolValue = value => typeof value === 'boolean' ? value : null;
const id = value => typeof value === 'string' && /^[A-Za-z0-9-]{1,128}$/.test(value)
  ? value : fail('INVALID_RESPONSE');
const urlFor = (pathname, fields = {}) => {
  const url = new URL(pathname, ORIGIN);
  for (const [key, value] of Object.entries(fields)) url.searchParams.set(key, value);
  return url.href;
};

function validateUrl(raw, code = 'UNSAFE_URL') {
  let url;
  try { url = new URL(raw); } catch { fail(code); }
  if (url.origin !== ORIGIN || url.username || url.password || url.hash || url.href.length > 8192
      || !/^\/v1\/(apps|builds|betaTesters|betaGroups|users)(\/|$)/.test(url.pathname)) fail(code);
  return url;
}

// Public API parameters checked against Apple's DocC reference, 2026-10-08:
// developer.apple.com/documentation/appstoreconnectapi/get-v1-betatesters
// .../get-v1-users ; .../get-v1-betagroups-_id_-betatesters
// Pagination may change only cursor; filters, field selection, endpoint and limits stay fixed.
function validateNext(raw, initial) {
  const next = validateUrl(raw, 'UNSAFE_PAGINATION');
  if (next.pathname !== initial.pathname) fail('UNSAFE_PAGINATION');
  for (const key of new Set([...initial.searchParams.keys(), ...next.searchParams.keys()])) {
    if (key === 'cursor') {
      if (next.searchParams.getAll(key).length > 1 || (next.searchParams.get(key)?.length ?? 0) > 2048)
        fail('UNSAFE_PAGINATION');
    } else if (JSON.stringify(initial.searchParams.getAll(key)) !== JSON.stringify(next.searchParams.getAll(key))) {
      fail('UNSAFE_PAGINATION');
    }
  }
  return next;
}

export function createReader({ authorization, fetchImpl = fetch, maxPages = 5,
  maxRequests = 60, timeoutMs = 8000, maxBytes = 1048576 } = {}) {
  let requests = 0;
  async function get(rawUrl, { method = 'GET' } = {}) {
    if (method !== 'GET') fail('READ_ONLY_REQUIRED');
    const url = validateUrl(rawUrl);
    if (++requests > maxRequests) fail('REQUEST_LIMIT');
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    let response;
    try {
      response = await fetchImpl(url.href, { method: 'GET', redirect: 'error',
        headers: { Authorization: authorization, Accept: 'application/json' }, signal: controller.signal });
      if (!response.ok) {
        // Do not read Apple's private error body or echo URLs, headers, or transport messages.
        await response.body?.cancel?.().catch(() => {});
        fail(({ 401: 'HTTP_UNAUTHORIZED', 403: 'HTTP_FORBIDDEN', 404: 'HTTP_NOT_FOUND',
          429: 'HTTP_RATE_LIMITED' })[response.status] ?? 'HTTP_ERROR');
      }
      const reader = response.body?.getReader?.();
      if (!reader) fail('INVALID_RESPONSE');
      const chunks = []; let length = 0;
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        length += value.byteLength;
        if (length > maxBytes) { await reader.cancel().catch(() => {}); fail('RESPONSE_TOO_LARGE'); }
        chunks.push(Buffer.from(value));
      }
      let parsed;
      try { parsed = JSON.parse(Buffer.concat(chunks).toString('utf8')); }
      catch { fail('INVALID_RESPONSE'); }
      if (!parsed || typeof parsed !== 'object' || !Object.hasOwn(parsed, 'data')) fail('INVALID_RESPONSE');
      return parsed;
    } catch (error) {
      if (error instanceof CheckError) throw error;
      fail(controller.signal.aborted ? 'TIMEOUT' : 'NETWORK_ERROR');
    } finally { clearTimeout(timer); }
  }
  async function list(rawUrl) {
    const initial = validateUrl(rawUrl); let next = initial; const seen = new Set(); const items = [];
    for (let page = 0; next; page++) {
      if (seen.has(next.href)) fail('PAGINATION_CYCLE');
      if (page >= maxPages) fail('PAGE_LIMIT');
      seen.add(next.href);
      const result = await get(next.href);
      if (!Array.isArray(result.data)) fail('INVALID_RESPONSE');
      items.push(...result.data);
      const link = result.links?.next;
      if (link !== undefined && link !== null && typeof link !== 'string') fail('INVALID_RESPONSE');
      next = link ? validateNext(link, initial) : null;
    }
    return items;
  }
  return Object.freeze({ get, list });
}

function typed(items, type) {
  for (const item of items) if (item?.type !== type || !item.attributes) fail('INVALID_RESPONSE');
  return items;
}
function uniqueOwner(items, field) {
  const matches = items.filter(item => typeof item.attributes?.[field] === 'string'
    && item.attributes[field].toLowerCase() === TARGET.email);
  if (matches.length > 1) fail('AMBIGUOUS_OWNER');
  return matches[0];
}

function ownTesterProfiles(items) {
  const matches = items.filter(item => typeof item.attributes.email === 'string'
    && item.attributes.email.toLowerCase() === TARGET.email);
  const profiles = new Map();
  const signature = item => JSON.stringify({ email: typeof item.attributes.email === 'string'
    ? item.attributes.email.toLowerCase() : item.attributes.email,
    state: item.attributes.state, inviteType: item.attributes.inviteType });
  for (const item of matches) {
    const profileId = id(item.id);
    const prior = profiles.get(profileId);
    if (prior && signature(prior) !== signature(item)) fail('CONFLICTING_OWNER_PROFILE');
    profiles.set(profileId, item);
  }
  // A repeated own ID with a contradictory email must not disappear as an unrelated row.
  for (const item of items) {
    const prior = profiles.get(item.id);
    if (prior && signature(prior) !== signature(item)) fail('CONFLICTING_OWNER_PROFILE');
  }
  if (profiles.size > 10) fail('OWNER_PROFILE_LIMIT');
  return { items: [...profiles.values()], matchedRecords: matches.length,
    uniqueProfiles: profiles.size, repeatedRecords: matches.length - profiles.size };
}

export async function runInstallCheck(reader) {
  const report = { complete: true, physicalInstallationVerified: false,
    app: { identityMatches: null },
    build: { exactMatch: null, processingState: 'UNKNOWN', expired: null,
      internalBuildState: 'UNKNOWN', externalBuildState: 'UNKNOWN' },
    groups: { internalAllBuildsGroupExists: null },
    owner: {
      tester: { exists: null, matchedRecords: null, uniqueProfiles: null, repeatedRecords: null,
        multipleProfiles: null, aggregation: 'ANY_PROFILE', state: 'UNKNOWN', inviteType: 'UNKNOWN',
        appMember: null, appGroupMember: null, internalAllBuildsGroupMember: null,
        exactBuildInMemberGroup: null, profiles: [] },
      appStoreUser: { exists: null, roles: [], allAppsVisible: null, appAccess: null },
    }, errors: [] };
  const record = (section, error, profileOrdinal) => {
    report.complete = false; report.errors.push({ section, status: safeCode(error),
      ...(profileOrdinal ? { profileOrdinal } : {}) });
  };
  const attempt = async (section, callback, profileOrdinal) => {
    try { return await callback(); } catch (error) { record(section, error, profileOrdinal); }
  };
  await attempt('app', async () => {
    const { data } = await reader.get(urlFor(`/v1/apps/${TARGET.app}`, { 'fields[apps]': 'bundleId' }));
    report.app.identityMatches = data?.type === 'apps' && data.id === TARGET.app
      && data.attributes?.bundleId === TARGET.bundle;
    if (!report.app.identityMatches) fail('APP_IDENTITY_MISMATCH');
  });
  if (report.app.identityMatches !== true) return report;

  let exactBuild;
  await attempt('build', async () => {
    const builds = await reader.list(urlFor('/v1/builds', { 'filter[app]': TARGET.app,
      'filter[version]': TARGET.build, 'fields[builds]': 'version,processingState,expired,app',
      include: 'app', 'fields[apps]': 'bundleId', limit: '20' }));
    const exact = builds.filter(build => build?.type === 'builds' && build.attributes?.version === TARGET.build
      && build.relationships?.app?.data?.type === 'apps' && build.relationships.app.data.id === TARGET.app);
    report.build.exactMatch = exact.length === 1;
    if (!report.build.exactMatch) fail('EXACT_BUILD_NOT_FOUND');
    exactBuild = id(exact[0].id);
    report.build.processingState = enumValue(exact[0].attributes.processingState, ['PROCESSING', 'FAILED', 'INVALID', 'VALID']);
    report.build.expired = boolValue(exact[0].attributes.expired);
    const { data } = await reader.get(urlFor(`/v1/builds/${exactBuild}/buildBetaDetail`, {
      'fields[buildBetaDetails]': 'internalBuildState,externalBuildState' }));
    if (data?.type !== 'buildBetaDetails') fail('INVALID_RESPONSE');
    report.build.internalBuildState = enumValue(data.attributes?.internalBuildState, INTERNAL_STATES);
    report.build.externalBuildState = enumValue(data.attributes?.externalBuildState, EXTERNAL_STATES);
  });

  let ownedProfiles;
  await attempt('tester', async () => {
    const items = typed(await reader.list(urlFor('/v1/betaTesters', { 'filter[email]': TARGET.email,
      'fields[betaTesters]': 'email,state,inviteType', limit: '20' })), 'betaTesters');
    const own = ownTesterProfiles(items);
    ownedProfiles = own.items.map((tester, index) => ({ tester, profile: {
      ordinal: index + 1, state: enumValue(tester.attributes.state, TESTER_STATES),
      inviteType: enumValue(tester.attributes.inviteType, ['EMAIL', 'PUBLIC_LINK']),
      appMember: null, appGroupMember: null, internalAllBuildsGroupMember: null, exactBuildInMemberGroup: null,
    } }));
    Object.assign(report.owner.tester, { exists: ownedProfiles.length > 0,
      matchedRecords: own.matchedRecords, uniqueProfiles: own.uniqueProfiles,
      repeatedRecords: own.repeatedRecords, multipleProfiles: own.uniqueProfiles > 1,
      profiles: ownedProfiles.map(owned => owned.profile) });
    if (!ownedProfiles.length) {
      Object.assign(report.owner.tester, { appMember: false, appGroupMember: false,
        internalAllBuildsGroupMember: false, exactBuildInMemberGroup: false });
      return;
    }
    if (ownedProfiles.length === 1) {
      report.owner.tester.state = ownedProfiles[0].profile.state;
      report.owner.tester.inviteType = ownedProfiles[0].profile.inviteType;
    }
  });
  for (const owned of ownedProfiles ?? []) await attempt('testerApp', async () => {
    const apps = typed(await reader.list(urlFor(`/v1/betaTesters/${id(owned.tester.id)}/apps`, {
      'fields[apps]': 'bundleId', limit: '200' })), 'apps');
    owned.profile.appMember = apps.some(app => app.id === TARGET.app && app.attributes.bundleId === TARGET.bundle);
  }, owned.profile.ordinal);

  await attempt('groups', async () => {
    const rows = typed(await reader.list(urlFor(`/v1/apps/${TARGET.app}/betaGroups`, {
      'fields[betaGroups]': 'isInternalGroup,hasAccessToAllBuilds', limit: '200' })), 'betaGroups');
    const groupsById = new Map();
    for (const group of rows) {
      const groupId = id(group.id); const prior = groupsById.get(groupId);
      if (prior && (prior.attributes.isInternalGroup !== group.attributes.isInternalGroup
          || prior.attributes.hasAccessToAllBuilds !== group.attributes.hasAccessToAllBuilds)) fail('INVALID_RESPONSE');
      groupsById.set(groupId, group);
    }
    const groups = [...groupsById.values()];
    if (groups.length > 20) fail('GROUP_LIMIT');
    report.groups.internalAllBuildsGroupExists = groups.some(group =>
      group.attributes.isInternalGroup === true && group.attributes.hasAccessToAllBuilds === true);
    if (!ownedProfiles?.length) return;
    // Only IDs/status fields of other members enter memory; no names, emails or device details requested.
    for (const owned of ownedProfiles) Object.assign(owned.profile, {
      appGroupMember: false, internalAllBuildsGroupMember: false, exactBuildInMemberGroup: exactBuild ? false : null,
    });
    const unknownUnlessProven = (profile, field) => { if (profile[field] !== true) profile[field] = null; };
    for (const group of groups) {
      const groupId = id(group.id);
      const allBuilds = group.attributes.isInternalGroup === true && group.attributes.hasAccessToAllBuilds === true;
      // Read each distinct group once, then compare all validated own IDs in memory.
      const members = await attempt('groupMembers', async () => typed(await reader.list(urlFor(
        `/v1/betaGroups/${groupId}/betaTesters`, { 'fields[betaTesters]': 'state,inviteType', limit: '200' })), 'betaTesters'));
      if (!members) {
        for (const { profile } of ownedProfiles) {
          unknownUnlessProven(profile, 'appGroupMember');
          if (allBuilds) unknownUnlessProven(profile, 'internalAllBuildsGroupMember');
          unknownUnlessProven(profile, 'exactBuildInMemberGroup');
        }
        continue;
      }
      const memberIds = new Set(members.map(item => item.id));
      const inGroup = ownedProfiles.filter(owned => memberIds.has(owned.tester.id));
      for (const { profile } of inGroup) {
        profile.appGroupMember = true;
        if (allBuilds) profile.internalAllBuildsGroupMember = true;
      }
      if (exactBuild && inGroup.length) {
        const builds = await attempt('groupBuilds', async () => typed(await reader.list(urlFor(
          `/v1/betaGroups/${groupId}/builds`, { 'fields[builds]': 'version', limit: '200' })), 'builds'));
        for (const { profile } of inGroup) {
          if (!builds) unknownUnlessProven(profile, 'exactBuildInMemberGroup');
          else if (builds.some(item => item.id === exactBuild && item.attributes.version === TARGET.build)) {
            profile.exactBuildInMemberGroup = true;
          }
        }
      }
    }
  });
  if (ownedProfiles?.length) for (const field of ['appMember', 'appGroupMember',
    'internalAllBuildsGroupMember', 'exactBuildInMemberGroup']) {
    const values = ownedProfiles.map(owned => owned.profile[field]);
    report.owner.tester[field] = values.includes(true) ? true : values.includes(null) ? null : false;
  }

  await attempt('appStoreUser', async () => {
    const users = typed(await reader.list(urlFor('/v1/users', { 'filter[username]': TARGET.email,
      'fields[users]': 'username,roles,allAppsVisible', limit: '20' })), 'users');
    const user = uniqueOwner(users, 'username'); report.owner.appStoreUser.exists = Boolean(user);
    if (!user) { report.owner.appStoreUser.appAccess = false; return; }
    id(user.id);
    report.owner.appStoreUser.roles = [...new Set((Array.isArray(user.attributes.roles) ? user.attributes.roles : [])
      .filter(role => ROLES.includes(role)))].sort();
    report.owner.appStoreUser.allAppsVisible = boolValue(user.attributes.allAppsVisible);
    if (user.attributes.allAppsVisible === true) { report.owner.appStoreUser.appAccess = true; return; }
    const apps = typed(await reader.list(urlFor(`/v1/users/${id(user.id)}/visibleApps`, {
      'fields[apps]': 'bundleId', limit: '200' })), 'apps');
    report.owner.appStoreUser.appAccess = apps.some(app => app.id === TARGET.app && app.attributes.bundleId === TARGET.bundle);
  });
  return report;
}

function ciAuthorization(env) {
  if (env.GITHUB_ACTIONS !== 'true') fail('CI_REQUIRED');
  const { KEY_ID, ISSUER_ID, KEY_P8_B64 } = env;
  if (!KEY_ID || !ISSUER_ID || !KEY_P8_B64) fail('CREDENTIALS_UNAVAILABLE');
  try {
    const header = Buffer.from(JSON.stringify({ alg: 'ES256', kid: KEY_ID, typ: 'JWT' })).toString('base64url');
    const now = Math.floor(Date.now() / 1000);
    const payload = Buffer.from(JSON.stringify({ iss: ISSUER_ID, iat: now, exp: now + 1100,
      aud: 'appstoreconnect-v1' })).toString('base64url');
    const unsigned = `${header}.${payload}`;
    const sign = createSign('SHA256'); sign.update(unsigned); sign.end();
    const signature = sign.sign({ key: Buffer.from(KEY_P8_B64, 'base64').toString('utf8'),
      dsaEncoding: 'ieee-p1363' }).toString('base64url');
    return `Bearer ${unsigned}.${signature}`;
  } catch { fail('SIGNING_FAILED'); }
}

async function main() {
  let report;
  try { report = await runInstallCheck(createReader({ authorization: ciAuthorization(process.env) })); }
  catch (error) { report = { complete: false, physicalInstallationVerified: false,
    errors: [{ section: 'setup', status: safeCode(error) }] }; }
  // The only persisted output is an explicitly constructed safe report, never raw Apple JSON or key material.
  try {
    if (!process.env.RUNNER_TEMP) fail('OUTPUT_FAILED');
    await writeFile(path.join(process.env.RUNNER_TEMP, 'testflight-install-check.json'),
      `${JSON.stringify(report, null, 2)}\n`, { mode: 0o600 });
  } catch { console.error('TestFlight diagnostic: OUTPUT_FAILED'); process.exitCode = 1; return; }
  console.log(`TestFlight diagnostic: ${report.complete ? 'READ_COMPLETE' : 'READ_INCOMPLETE'}`);
  if (!report.complete) process.exitCode = 1;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await main();
