import UIKit
import Capacitor
import UserNotifications

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    var window: UIWindow?
    private let bridgeQueue = OfferBridgeQueue()
    private var bridgeFlushWorkItem: DispatchWorkItem?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        // Default-off until the authenticated web bridge supplies both the
        // canonical operational state and an enabled backend policy.
        LocationTracking.shared.apply(state: "offline", policyEnabled: false)

        scheduleBridgeFlush(attempt: 0)
        beacon("launch", "apns-only")
        return true
    }

    private func beacon(_ stage: String, _ extra: String = "") {
        // Diagnostic traces stay in the device log. The former unauthenticated
        // network beacon endpoint was intentionally removed from the backend.
        NSLog("[MiseDriver] %@ %@", stage, extra)
    }

    func applicationWillResignActive(_ application: UIApplication) {}
    func applicationDidEnterBackground(_ application: UIApplication) {
        LocationTracking.shared.enteredBackground()
    }
    func applicationWillEnterForeground(_ application: UIApplication) {}
    func applicationDidBecomeActive(_ application: UIApplication) {
        LocationTracking.shared.refreshServerAuthorization()
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
        if url.scheme == "mise-driver", url.host == "bridge-ready" {
            LocationTracking.shared.refreshServerAuthorization()
            scheduleBridgeFlush(attempt: 0)
            return true
        }
        if url.scheme == "mise-driver", url.host == "gps-refresh" {
            LocationTracking.shared.refreshServerAuthorization()
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

}
