import type { CapacitorConfig } from '@capacitor/cli';

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
  appId: 'app.mise.driver',
  appName: 'Mise Driver',
  webDir: 'web',
  server: {
    url: 'https://mise-gastro.de/driver',
    cleartext: false,
    androidScheme: 'https',
    allowNavigation: [
      'mise-gastro.de',
      '*.mise-gastro.de',
      'mise.app',
      '*.mise.app',
    ],
  },
  ios: {
    contentInset: 'always',
    backgroundColor: '#09090b',
    scheme: 'mise-driver',
    preferredContentMode: 'mobile',
    limitsNavigationsToAppBoundDomains: false,
  },
  android: {
    backgroundColor: '#09090b',
    allowMixedContent: false,
    captureInput: true,
    webContentsDebuggingEnabled: false,
  },
  plugins: {
    SplashScreen: {
      launchShowDuration: 1500,
      launchAutoHide: true,
      backgroundColor: '#09090b',
      androidSplashResourceName: 'splash',
      androidScaleType: 'CENTER_CROP',
      showSpinner: true,
      spinnerColor: '#fbbf24',
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
      backgroundColor: '#09090b',
      overlaysWebView: false,
    },
    Haptics: {},
  },
};

export default config;
