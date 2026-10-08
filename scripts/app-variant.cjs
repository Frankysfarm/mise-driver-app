'use strict';
const variants = require('../config/driver-variants.json');
const backends = require('../config/driver-backends.json');
function backendOrigin(target) {
  if (!Object.prototype.hasOwnProperty.call(backends, target)) throw new Error('Unknown DRIVER_BACKEND_TARGET; expected production or protected_preview.');
  const origin = backends[target];
  const url = new URL(origin);
  if (url.protocol !== 'https:' || url.username || url.password || url.port || url.pathname !== '/'
      || url.search || url.hash || url.origin !== origin) throw new Error('Driver backend must be an exact compiled HTTPS origin.');
  return origin;
}
function validateVariant(variant) {
  const mise = variant.name === 'mise' && variant.bundle_id === 'app.mise.driver';
  const frankys = variant.name === 'frankys' && variant.bundle_id === 'de.frankysfarm.driver';
  if ((!mise && !frankys)
      || variant.url_scheme !== (mise ? 'mise-driver' : 'frankys-driver')
      || variant.web_dir !== (mise ? 'web' : 'web-canary')
      || variant.server_origin !== backendOrigin(variant.backend_target ?? 'production')
      || frankys && (variant.backend_target ?? 'production') !== 'production'
      || variant.team_id !== 'T82KC2CU9V'
      || variant.installation_canary !== frankys || variant.operations_enabled !== mise) {
    throw new Error('Variant identity, navigation and capability metadata must match exactly.');
  }
  return variant;
}
function resolveVariant(name = process.env.DRIVER_APP_VARIANT ?? 'mise', target = process.env.DRIVER_BACKEND_TARGET ?? 'production') {
  if (!Object.prototype.hasOwnProperty.call(variants, name)) {
    throw new Error('Unknown DRIVER_APP_VARIANT; expected mise or frankys.');
  }
  return validateVariant({ name, ...variants[name], backend_target: target, server_origin: backendOrigin(target) });
}
function capacitorIdentity(variant = resolveVariant()) {
  validateVariant(variant);
  return {
    appId: variant.bundle_id,
    appName: variant.display_name,
    webDir: variant.web_dir,
    server: {
      ...(variant.installation_canary ? {} : { url: `${variant.server_origin}/fahrer/app` }),
      cleartext: false,
      androidScheme: 'https',
      allowNavigation: variant.installation_canary ? [] : [new URL(variant.server_origin).hostname],
    },
  };
}
module.exports = { resolveVariant, capacitorIdentity, validateVariant, backendOrigin };
