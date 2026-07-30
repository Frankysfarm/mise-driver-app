import UIKit
import Capacitor
import PushKit
import CallKit
import UserNotifications

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, PKPushRegistryDelegate, CXProviderDelegate, UNUserNotificationCenterDelegate {

    var window: UIWindow?
    var voipRegistry: PKPushRegistry?
    var callProvider: CXProvider?
    private let offerRegistry = OfferRegistry()
    private let bridgeQueue = OfferBridgeQueue()
    private var bridgeFlushWorkItem: DispatchWorkItem?
    private lazy var tokenUploader = VoipTokenUploader { [weak self] stage in
        self?.beacon(stage)
    }

    private var legacyVoipOffersEnabled: Bool {
        // Compatibility-only. APNs alert is the expected primary offer channel.
        // Set MiseLegacyVoipOffersEnabled=false once the server is APNs-first.
        (Bundle.main.object(forInfoDictionaryKey: "MiseLegacyVoipOffersEnabled") as? Bool) ?? true
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        // Legacy compatibility only. Normal delivery offers must arrive via APNs alert.
        let config = CXProviderConfiguration(localizedName: "Mise")
        config.supportsVideo = false
        config.maximumCallsPerCallGroup = 1
        config.maximumCallGroups = 1
        config.supportedHandleTypes = [.generic]
        config.ringtoneSound = "alarm.caf"
        let provider = CXProvider(configuration: config)
        provider.setDelegate(self, queue: nil)
        self.callProvider = provider

        if legacyVoipOffersEnabled {
            // Compatibility only. APNs-first builds do not register for PushKit.
            let registry = PKPushRegistry(queue: .main)
            registry.delegate = self
            registry.desiredPushTypes = [.voIP]
            self.voipRegistry = registry
        }
        // Default-off until the authenticated web bridge supplies both the
        // canonical operational state and an enabled backend policy.
        LocationTracking.shared.apply(state: "offline", policyEnabled: false)

        tokenUploader.reconcile()
        scheduleBridgeFlush(attempt: 0)
        beacon("launch", legacyVoipOffersEnabled ? "legacy-voip-enabled" : "apns-first")
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
    func applicationDidEnterBackground(_ application: UIApplication) {
        LocationTracking.shared.enteredBackground()
    }
    func applicationWillEnterForeground(_ application: UIApplication) {}
    func applicationDidBecomeActive(_ application: UIApplication) {
        LocationTracking.shared.refreshServerAuthorization()
        tokenUploader.reconcile()
        scheduleBridgeFlush(attempt: 0)
    }
    func applicationWillTerminate(_ application: UIApplication) {
        LocationTracking.shared.apply(state: "offline", policyEnabled: false)
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        if url.scheme == "mise-driver", url.host == "offer-ack",
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let eventId = components.queryItems?.first(where: { $0.name == "event_id" })?.value {
            acknowledgeBridgeEvent(eventId)
            return true
        }
        if url.scheme == "mise-driver", url.host == "auth-changed" {
            tokenUploader.authDidChange()
            return true
        }
        if url.scheme == "mise-driver", url.host == "bridge-ready" {
            scheduleBridgeFlush(attempt: 0)
            return true
        }
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

    // Standard APNs: bridge the exact immutable offer into the WebView.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        bridgeOffer(from: userInfo, stage: "received")
        completionHandler(.newData)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        bridgeOffer(from: notification.request.content.userInfo, stage: "displayed")
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound, .badge])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        bridgeOffer(from: response.notification.request.content.userInfo, stage: "opened")
        completionHandler()
    }

    // MARK: - PushKit (VoIP)
    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: "CapacitorStorage.mise_voip_token")
        beacon("voip-didupdate", "len=\(token.count)")
        tokenUploader.register(token)
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        UserDefaults.standard.removeObject(forKey: "CapacitorStorage.mise_voip_token")
        tokenUploader.invalidate()
        beacon("voip-token-invalidated")
    }

    // VoIP-Push empfangen -> SOFORT als eingehenden Anruf melden (iOS-13+-Pflicht)
    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        let dict = payload.dictionaryPayload
        guard let offer = OfferEnvelope.parse(dict) else {
            beacon("voip-invalid-payload")
            completion()
            return
        }
        bridge(offer, stage: "received")

        let restaurant = (dict["restaurant_name"] as? String) ?? "Neue Bestellung"
        let sub = (dict["body"] as? String) ?? "Tippe zum Annehmen"
        let uuid = UUID()
        offerRegistry.insert(offer, for: uuid)
        // A callback while disabled means the migration still has a residual
        // PushKit registration/server send. iOS requires it to be reported;
        // never silently complete it. Fresh APNs-first launches do not register.
        beacon(legacyVoipOffersEnabled ? "voip-incoming" : "voip-residual-reported", offer.offerId)

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: restaurant)
        update.localizedCallerName = "\(restaurant) — \(sub)"
        update.hasVideo = false
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false

        guard let callProvider else {
            offerRegistry.remove(for: uuid)
            beacon("voip-provider-missing", offer.offerId)
            completion()
            return
        }
        callProvider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
            if error != nil {
                self?.offerRegistry.remove(for: uuid)
                self?.beacon("voip-report-failed", offer.offerId)
            }
            completion()
        }
    }

    private func bridgeOffer(from payload: [AnyHashable: Any], stage: String) {
        guard let offer = OfferEnvelope.parse(payload) else {
            beacon("offer-invalid-payload", stage)
            return
        }
        bridge(offer, stage: stage)
    }

    private func bridge(_ offer: OfferEnvelope, stage: String) {
        let event = OfferBridgeEvent(offer: offer, stage: stage)
        queueBridgeEvent(event)
        guard let javaScript = event.bridgeJavaScript() else {
            beacon("offer-bridge-encode-failed", offer.offerId)
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let bridgeController = self?.findBridgeController(self?.window?.rootViewController),
                  let webView = bridgeController.bridge?.webView
            else {
                self?.queueBridgeEvent(event)
                self?.beacon("offer-bridge-not-ready", offer.offerId)
                return
            }
            webView.evaluateJavaScript(javaScript) { _, error in
                if error == nil {
                    // Evaluation only proves transport into WKWebView. Retain
                    // until the web consumer calls the explicit ACK URL.
                    self?.beacon("offer-transported-\(stage)", offer.offerId)
                } else {
                    self?.queueBridgeEvent(event)
                    self?.beacon("offer-bridge-failed", offer.offerId)
                }
            }
        }
    }

    private func queueBridgeEvent(_ event: OfferBridgeEvent) {
        bridgeQueue.enqueue(event)
    }

    private func acknowledgeBridgeEvent(_ eventId: String) {
        beacon(bridgeQueue.acknowledge(eventId: eventId) ? "offer-web-acked" : "offer-ack-unknown")
        if bridgeQueue.activeEvents().isEmpty {
            bridgeFlushWorkItem?.cancel()
            bridgeFlushWorkItem = nil
        }
    }

    private func scheduleBridgeFlush(attempt: Int) {
        bridgeFlushWorkItem?.cancel()
        guard let delay = BridgeReplayPolicy.delay(attempt: attempt) else {
            beacon("offer-replay-paused")
            return
        }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let events = self.bridgeQueue.activeEvents()
            for event in events {
                self.bridge(event.offer, stage: event.stage)
            }
            if !events.isEmpty {
                self.scheduleBridgeFlush(attempt: attempt + 1)
            }
        }
        bridgeFlushWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func findBridgeController(_ controller: UIViewController?) -> CAPBridgeViewController? {
        if let bridge = controller as? CAPBridgeViewController { return bridge }
        if let presented = controller?.presentedViewController,
           let bridge = findBridgeController(presented) { return bridge }
        for child in controller?.children ?? [] {
            if let bridge = findBridgeController(child) { return bridge }
        }
        return nil
    }

    // MARK: - CallKit Delegate
    // Fahrer tippt „Annehmen" -> App in den Vordergrund holen (CallKit foregroundet automatisch),
    // Anruf sofort beenden damit CallKit-UI verschwindet. Die Web-UI macht den eigentlichen Claim
    // via visibilitychange-Reload → kein Race mit dem nativen acceptTour-Pfad.
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        guard let offer = offerRegistry.offer(for: action.callUUID) else {
            beacon("callkit-answer-unmapped")
            action.fail()
            return
        }
        // Persist the bridge event before removing the CallKit mapping.
        bridge(offer, stage: "answered")
        offerRegistry.remove(for: action.callUUID)
        beacon("callkit-answered", offer.offerId)
        action.fulfill()
        provider.reportCall(with: action.callUUID, endedAt: Date(), reason: .remoteEnded)
    }

    // Fahrer lehnt ab / legt auf
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        if let offer = offerRegistry.offer(for: action.callUUID) {
            bridge(offer, stage: "ended")
            offerRegistry.remove(for: action.callUUID)
        }
        action.fulfill()
    }

    func providerDidReset(_ provider: CXProvider) {
        offerRegistry.removeAll()
    }
}

private final class VoipTokenUploader {
    private struct Pending: Codable {
        let token: String
        var attempt: Int
    }

    private let defaults = UserDefaults.standard
    private let pendingKey = "mise_voip_token_upload_pending_v1"
    private let accessKey = "CapacitorStorage.mise_access_token"
    private let endpoint = URL(string: "https://mise-gastro.de/api/driver/v1/me/voip-token")!
    private let report: (String) -> Void
    private var scheduled: DispatchWorkItem?
    private var inFlight = false
    private var reconcileAfterCompletion = false

    init(report: @escaping (String) -> Void) {
        self.report = report
    }

    func register(_ token: String) {
        persist(Pending(token: token, attempt: 0))
        reconcile()
    }

    func invalidate() {
        scheduled?.cancel()
        scheduled = nil
        defaults.removeObject(forKey: pendingKey)
    }

    func reconcile() {
        guard !inFlight, let pending = load() else { return }
        guard let access = defaults.string(forKey: accessKey), !access.isEmpty else {
            report("voip-token-awaiting-auth")
            return
        }
        upload(pending, access: access)
    }

    func authDidChange() {
        scheduled?.cancel()
        scheduled = nil
        if inFlight {
            reconcileAfterCompletion = true
            return
        }
        reconcile()
    }

    private func upload(_ pending: Pending, access: String) {
        inFlight = true
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["token": pending.token])

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight = false
                let authChangedWhileInFlight = self.reconcileAfterCompletion
                self.reconcileAfterCompletion = false
                let status = (response as? HTTPURLResponse)?.statusCode
                let newest = self.load()
                let action = TokenRetryPolicy.completionAction(
                    attemptedToken: pending.token,
                    newestToken: newest?.token,
                    attempt: pending.attempt,
                    statusCode: status,
                    hadNetworkError: error != nil
                )
                switch action {
                case .superseded:
                    self.report("voip-token-superseded")
                    self.reconcile()
                case .synced:
                    if newest?.token == pending.token {
                        self.defaults.removeObject(forKey: self.pendingKey)
                    }
                    self.report("voip-token-synced")
                    // Always inspect state again: register() may have installed a
                    // newer token between response and completion handling.
                    self.reconcile()
                case .awaitAuthChange:
                    self.report("voip-token-awaiting-reconcile")
                    if authChangedWhileInFlight { self.reconcile() }
                case .retry(let nextAttempt):
                    // Do not overwrite a token that rotated during this request.
                    guard self.load()?.token == pending.token else {
                        self.reconcile()
                        return
                    }
                    var next = pending
                    next.attempt = nextAttempt
                    self.persist(next)
                    if authChangedWhileInFlight {
                        self.reconcile()
                    } else {
                        self.schedule(next)
                    }
                }
            }
        }.resume()
    }

    private func schedule(_ pending: Pending) {
        scheduled?.cancel()
        let delay = TokenRetryPolicy.delay(attempt: pending.attempt, jitterUnit: Double.random(in: 0...1))
        let item = DispatchWorkItem { [weak self] in self?.reconcile() }
        scheduled = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        report("voip-token-retry-scheduled")
    }

    private func persist(_ pending: Pending) {
        if let data = try? JSONEncoder().encode(pending) {
            defaults.set(data, forKey: pendingKey)
        }
    }

    private func load() -> Pending? {
        guard let data = defaults.data(forKey: pendingKey) else { return nil }
        return try? JSONDecoder().decode(Pending.self, from: data)
    }
}
