'use strict';
const variants = require('../config/driver-variants.json');
function validateVariant(variant) {
  const mise = variant.name === 'mise' && variant.bundle_id === 'app.mise.driver';
  const frankys = variant.name === 'frankys' && variant.bundle_id === 'de.frankysfarm.driver';
  if ((!mise && !frankys)
      || variant.url_scheme !== (mise ? 'mise-driver' : 'frankys-driver')
      || variant.web_dir !== (mise ? 'web' : 'web-canary')
      || variant.server_origin !== 'https://mise-gastro.de'
      || variant.team_id !== 'T82KC2CU9V'
      || variant.installation_canary !== frankys || variant.operations_enabled !== mise) {
    throw new Error('Variant identity, navigation and capability metadata must match exactly.');
  }
  return variant;
}
function resolveVariant(name = process.env.DRIVER_APP_VARIANT ?? 'mise') {
  if (!Object.prototype.hasOwnProperty.call(variants, name)) {
    throw new Error('Unknown DRIVER_APP_VARIANT; expected mise or frankys.');
  }
  return validateVariant({ name, ...variants[name] });
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
      allowNavigation: variant.installation_canary ? [] : ['mise-gastro.de', '*.mise-gastro.de', 'mise.app', '*.mise.app'],
    },
  };
}
module.exports = { resolveVariant, capacitorIdentity, validateVariant };
