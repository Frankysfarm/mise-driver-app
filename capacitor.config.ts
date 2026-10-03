import type { CapacitorConfig } from '@capacitor/cli';

const { resolveVariant, capacitorIdentity } = require('./scripts/app-variant.cjs');
const variant = resolveVariant();
const shellBackground = variant.installation_canary ? '#F6EDDA' : '#09090b';

/**
 * Mise Driver — Capacitor-Konfiguration für die native Fahrer-App.
 *
 * WebView-Strategie: lädt Live-URL (mise-gastro.de/driver). So bleibt der
 * Driver-Web-Code im Mise-Backoffice und Updates erscheinen ohne neuen App-Store-Build.
 *
 * Native-Permissions:
 *   - Geolocation (Hintergrund + Vordergrund) für Live-Tracking während Lieferung
 *   - Camera für QR-Scan + Liefer-Foto-Beweis
 *   - Push-Notifications für eingehende Bestellungen
 *   - Haptik-Feedback bei Bestellungs-Annahme
 *
 * MULTI-TENANT: Eine App, alle Restaurants. Driver loggt sich mit seinem
 * persönlichen Account ein → sieht nur Bestellungen seiner zugewiesenen Filiale.
 */
const config: CapacitorConfig = {
  // Shared resolver keeps the canary local and preserves the default live URL.
  ...capacitorIdentity(variant),
  ios: {
    contentInset: 'always',
    backgroundColor: shellBackground,
    scheme: variant.url_scheme,
    preferredContentMode: 'mobile',
    limitsNavigationsToAppBoundDomains: false,
  },
  android: {
    backgroundColor: shellBackground,
    allowMixedContent: false,
    captureInput: true,
    webContentsDebuggingEnabled: false,
  },
  plugins: {
    SplashScreen: {
      launchShowDuration: 1500,
      launchAutoHide: true,
      backgroundColor: shellBackground,
      androidSplashResourceName: 'splash',
      androidScaleType: 'CENTER_CROP',
      showSpinner: true,
      spinnerColor: variant.installation_canary ? '#194B35' : '#fbbf24',
    },
    Geolocation: {
      // iOS Info.plist Keys werden in Info.plist gepflegt; hier nur Capacitor-Defaults
    },
    Camera: {
      // iOS Info.plist Keys werden in Info.plist gepflegt
    },
    PushNotifications: {
      presentationOptions: ['badge', 'sound', 'alert'],
    },
    StatusBar: {
      style: 'DARK',
      backgroundColor: shellBackground,
      overlaysWebView: false,
    },
    Haptics: {},
  },
};

export default config;
