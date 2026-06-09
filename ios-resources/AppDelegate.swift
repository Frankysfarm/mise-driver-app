import UIKit
import Capacitor
import PushKit
import CallKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, PKPushRegistryDelegate, CXProviderDelegate {

    var window: UIWindow?
    var voipRegistry: PKPushRegistry?
    var callProvider: CXProvider?
    var currentCallUUID: UUID?
    var currentBatchId: String?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // CallKit: konfiguriert den eingehenden „Anruf" (Vollbild + Dauer-Klingeln)
        let config = CXProviderConfiguration(localizedName: "Mise")
        config.supportsVideo = false
        config.maximumCallsPerCallGroup = 1
        config.maximumCallGroups = 1
        config.supportedHandleTypes = [.generic]
        config.ringtoneSound = "alarm.caf"
        let provider = CXProvider(configuration: config)
        provider.setDelegate(self, queue: nil)
        self.callProvider = provider

        // PushKit: VoIP-Token registrieren
        let registry = PKPushRegistry(queue: .main)
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
        self.voipRegistry = registry

        beacon("launch", "callkit+pushkit setup")
        return true
    }

    private func beacon(_ stage: String, _ extra: String = "") {
        guard let url = URL(string: "https://mise-gastro.de/api/driver/v1/push-debug") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["stage": "native-" + stage, "data": extra])
        URLSession.shared.dataTask(with: req).resume()
    }

    func applicationWillResignActive(_ application: UIApplication) {}
    func applicationDidEnterBackground(_ application: UIApplication) {}
    func applicationWillEnterForeground(_ application: UIApplication) {}
    func applicationDidBecomeActive(_ application: UIApplication) {}
    func applicationWillTerminate(_ application: UIApplication) {}

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return ApplicationDelegateProxy.shared.application(app, open: url, options: options)
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        return ApplicationDelegateProxy.shared.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }

    // Standard-Remote-Notifications -> Capacitor (normaler Push)
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationCenter.default.post(name: .capacitorDidRegisterForRemoteNotifications, object: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationCenter.default.post(name: .capacitorDidFailToRegisterForRemoteNotifications, object: error)
    }

    // MARK: - PushKit (VoIP)
    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: "CapacitorStorage.mise_voip_token")
        beacon("voip-didupdate", "len=\(token.count)")
        postVoipToken(token)
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        UserDefaults.standard.removeObject(forKey: "CapacitorStorage.mise_voip_token")
    }

    // VoIP-Push empfangen -> SOFORT als eingehenden Anruf melden (iOS-13+-Pflicht)
    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        let dict = payload.dictionaryPayload
        let restaurant = (dict["restaurant_name"] as? String) ?? "Neue Bestellung"
        let sub = (dict["body"] as? String) ?? "Tippe zum Annehmen"
        beacon("voip-incoming", restaurant)
        self.currentBatchId = dict["batch_id"] as? String
        let uuid = UUID()
        self.currentCallUUID = uuid

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: restaurant)
        update.localizedCallerName = "\(restaurant) — \(sub)"
        update.hasVideo = false
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false

        callProvider?.reportNewIncomingCall(with: uuid, update: update) { _ in
            completion()
        }
    }

    private func postVoipToken(_ token: String) {
        guard let access = UserDefaults.standard.string(forKey: "CapacitorStorage.mise_access_token"),
              let url = URL(string: "https://mise-gastro.de/api/driver/v1/me/voip-token-save") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["voip_push_token": token])
        URLSession.shared.dataTask(with: req).resume()
    }

    // MARK: - CallKit Delegate
    func providerDidReset(_ provider: CXProvider) {}

    // Fahrer tippt „Annehmen" -> App in den Vordergrund holen (CallKit foregroundet automatisch),
    // dann Anruf beenden (wir wollten nur Klingeln + Öffnen).
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        // Anruf annehmen = Tour automatisch annehmen
        acceptTour()
        action.fulfill()
        if let uuid = currentCallUUID {
            provider.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
            currentCallUUID = nil
        }
    }

    private func acceptTour() {
        beacon("accept-tour", currentBatchId ?? "no-batch")
        guard let access = UserDefaults.standard.string(forKey: "CapacitorStorage.mise_access_token"),
              let url = URL(string: "https://mise-gastro.de/api/driver/v1/me/accept-tour") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["batch_id": currentBatchId ?? ""])
        URLSession.shared.dataTask(with: req).resume()
    }

    // Fahrer lehnt ab / legt auf
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        action.fulfill()
        currentCallUUID = nil
    }
}
