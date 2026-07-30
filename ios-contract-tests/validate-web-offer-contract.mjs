import fs from 'node:fs';

const path = process.argv[2];
if (!path) throw new Error('usage: validate-web-offer-contract.mjs native-payload.json');
const detail = JSON.parse(fs.readFileSync(path, 'utf8'));

const valid =
  typeof detail.event_id === 'string' &&
  detail.event_id.length > 0 &&
  typeof detail.stage === 'string' &&
  typeof detail.offer_id === 'string' &&
  detail.offer_id.length > 0 &&
  typeof detail.batch_id === 'string' &&
  detail.batch_id.length > 0 &&
  Number.isSafeInteger(detail.assignment_version) &&
  detail.assignment_version >= 1 &&
  typeof detail.ack_url === 'string' &&
  detail.ack_url.startsWith('mise-driver://offer-ack?event_id=') &&
  !Object.hasOwn(detail, 'offer');

if (!valid) {
  console.error('FAIL: Swift payload does not satisfy NativeOfferBridge top-level contract', detail);
  process.exit(1);
}

console.log('PASS: Swift payload satisfies web NativeOfferBridge contract');
