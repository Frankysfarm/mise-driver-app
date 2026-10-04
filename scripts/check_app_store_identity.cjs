'use strict';
const crypto = require('node:crypto');
function validateRecord(record, appleAppId, bundleId) {
  if (record?.data?.id !== appleAppId || record?.data?.attributes?.bundleId !== bundleId) {
    throw new Error('Apple app record does not match the selected app ID and bundle ID.');
  }
}
async function main() {
  const { KEY_ID, ISSUER_ID, APP_ID, BUNDLE_ID, KEY_P8_B64 } = process.env;
  if (![KEY_ID, ISSUER_ID, APP_ID, BUNDLE_ID, KEY_P8_B64].every(Boolean)) {
    throw new Error('Missing Apple API credentials or resolved app identity.');
  }
  const now = Math.floor(Date.now() / 1000);
  const header = Buffer.from(JSON.stringify({ alg: 'ES256', kid: KEY_ID, typ: 'JWT' })).toString('base64url');
  const payload = Buffer.from(JSON.stringify({ iss: ISSUER_ID, iat: now, exp: now + 300, aud: 'appstoreconnect-v1' })).toString('base64url');
  const message = `${header}.${payload}`;
  let signature;
  try {
    signature = crypto.sign('sha256', Buffer.from(message), {
      key: Buffer.from(KEY_P8_B64, 'base64'), dsaEncoding: 'ieee-p1363',
    }).toString('base64url');
  } catch { throw new Error('Configured Apple API signing key could not be used.'); }
  const response = await fetch(`https://api.appstoreconnect.apple.com/v1/apps/${APP_ID}?fields[apps]=bundleId`, {
    headers: { Authorization: `Bearer ${message}.${signature}` }, signal: AbortSignal.timeout(20000),
  });
  if (!response.ok) throw new Error(`Apple app identity verification failed (HTTP ${response.status}).`);
  validateRecord(await response.json(), APP_ID, BUNDLE_ID);
  console.log('Apple app record matches the selected build identity.');
}
module.exports = { validateRecord };
if (require.main === module) main().catch(error => { console.error(error.message); process.exit(1); });
