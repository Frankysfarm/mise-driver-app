import CoreLocation
import Foundation
import Security
import UIKit

final class LocationTracking: NSObject, CLLocationManagerDelegate {
    static let shared = LocationTracking()
    private let manager = CLLocationManager()
    private let defaults = UserDefaults.standard
    private let runtime = DriverRuntimeConfiguration.current
    private let sequenceKey = "mise.gps.sequence.v2"
    private let sessionKey = "mise.gps.session.v2"
    private let installationKey = "mise.gps.installation.v2"
    private let allowed = Set(["available", "assigned", "at_pickup", "delivering", "returning"])
    private(set) var operationalState = "offline"
    private(set) var policyEnabled = false
    private(set) var driverVersion = 0
    private(set) var backgroundPolicyEnabled = false
    private var session = GpsSessionState()
    private var authorizationTask: URLSessionDataTask?
    private var authorizationRequestID: UUID?
    private var uploadTask: URLSessionDataTask?
    private var uploadRequestID: UUID?
    private var retryWorkItem: DispatchWorkItem?
    private let credentialHandoffKey = "CapacitorStorage.mise_access_token"
    private var retrySeconds: TimeInterval = 1
    private let tokenAccount = "mise.driver.access-token"

    override private init() {
        super.init()
        // A persisted credential is not evidence of a current WebView login.
        // The existing web bridge supplies a fresh handoff after launch.
        defaults.removeObject(forKey: credentialHandoffKey)
        deleteLegacyToken()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 15
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = true
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    func apply(state: String, driverVersion: Int = 0, policyEnabled: Bool, backgroundPolicyEnabled: Bool = false) {
        precondition(Thread.isMainThread)
        let authorityChanged = operationalState != state || self.driverVersion != driverVersion
        self.operationalState = state
        self.driverVersion = driverVersion
        self.policyEnabled = policyEnabled
        self.backgroundPolicyEnabled = backgroundPolicyEnabled
        if authorityChanged {
            defaults.set(UUID().uuidString.lowercased(), forKey: sessionKey)
            defaults.set(0, forKey: sequenceKey)
        }
        guard runtime.operationsEnabled,
              policyEnabled, allowed.contains(state), let context = session.context,
              session.matches(context), session.authorizedSince != nil,
              UIApplication.shared.applicationState == .active || backgroundPolicyEnabled else {
            session.suspend()
            manager.stopUpdatingLocation()
            manager.stopMonitoringSignificantLocationChanges()
            cancelUpload()
            defaults.removeObject(forKey: sessionKey)
            defaults.set(0, forKey: sequenceKey)
            return
        }
        if currentAuthorizationStatus() == .notDetermined { manager.requestAlwaysAuthorization() }
        manager.startUpdatingLocation()
        manager.startMonitoringSignificantLocationChanges()
        flush()
    }

    func refreshServerAuthorization() {
        precondition(Thread.isMainThread)
        guard let context = currentContext(),
              let url = runtime.endpoint(path: "/api/driver/v2/snapshot") else {
            apply(state: "offline", policyEnabled: false); return
        }
        authorizationTask?.cancel()
        let requestID = UUID()
        authorizationRequestID = requestID
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Bearer \(context.token)", forHTTPHeaderField: "Authorization")
        authorizationTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                guard let self, self.authorizationRequestID == requestID,
                      self.currentContext() == context, self.session.matches(context) else { return }
                self.authorizationTask = nil
                self.authorizationRequestID = nil
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 401 || status == 403 { self.logout(); return }
                guard status == 200, let data,
                      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let snapshot = root["snapshot"] as? [String: Any],
                      let driver = snapshot["driver"] as? [String: Any],
                      let gps = snapshot["gps_transport"] as? [String: Any],
                      self.session.authorize(context) else {
                    self.apply(state: "offline", policyEnabled: false); return
                }
                self.apply(state: driver["state"] as? String ?? "offline",
                           driverVersion: driver["version"] as? Int ?? 0,
                           policyEnabled: gps["policy_enabled"] as? Bool ?? false,
                           backgroundPolicyEnabled: gps["background_policy_enabled"] as? Bool ?? false)
            }
        }
        authorizationTask?.resume()
    }

    func logout() {
        precondition(Thread.isMainThread)
        session.invalidate()
        authorizationTask?.cancel()
        authorizationTask = nil
        authorizationRequestID = nil
        defaults.removeObject(forKey: credentialHandoffKey)
        deleteLegacyToken()
        SecureGpsQueue.shared.clearQueue()
        retrySeconds = 1
        apply(state: "offline", policyEnabled: false)
    }

    func enteredBackground() {
        precondition(Thread.isMainThread)
        guard currentContext() != nil else { return }
        if !backgroundPolicyEnabled {
            session.suspend()
            manager.stopUpdatingLocation()
            manager.stopMonitoringSignificantLocationChanges()
            cancelUpload()
        } else {
            refreshServerAuthorization()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        precondition(Thread.isMainThread)
        guard let context = currentContext(), policyEnabled, allowed.contains(operationalState),
              let location = locations.last,
              session.permitsCapture(at: location.timestamp, context: context),
              location.horizontalAccuracy >= 0 else { return }
        if UIApplication.shared.applicationState != .active && !backgroundPolicyEnabled { return }
        let session = defaults.string(forKey: sessionKey) ?? {
            let id = UUID().uuidString.lowercased(); defaults.set(id, forKey: sessionKey); return id
        }()
        let sequence = defaults.integer(forKey: sequenceKey) + 1
        defaults.set(sequence, forKey: sequenceKey)
        let installation = defaults.string(forKey: installationKey) ?? {
            let id = UUID().uuidString.lowercased()
            defaults.set(id, forKey: installationKey)
            return id
        }()
        let state: String = UIApplication.shared.applicationState == .active ? "foreground" : "background"
        let batteryLevel = UIDevice.current.batteryLevel >= 0 ? Double(UIDevice.current.batteryLevel) : nil
        let batteryValue: Any = batteryLevel.map { $0 as Any } ?? NSNull()
        let charging = [UIDevice.BatteryState.charging, .full].contains(UIDevice.current.batteryState)
        let payload: [String: Any] = [
            "action_id": UUID().uuidString.lowercased(), "installation_id": installation,
            "session_id": session, "sequence": sequence,
            "captured_at": ISO8601DateFormatter().string(from: location.timestamp),
            "latitude": location.coordinate.latitude, "longitude": location.coordinate.longitude,
            "accuracy_m": location.horizontalAccuracy, "speed_mps": max(location.speed, 0),
            "heading_deg": location.course >= 0 ? location.course : NSNull(),
            "altitude_m": location.verticalAccuracy >= 0 ? location.altitude : NSNull(),
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "app_build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            "platform": "ios", "app_state": state, "permission_state": permission(),
            "network_state": "unknown",
            "tracking_mode": state == "foreground" ? "continuous" : "significant_change",
            "battery_state": [
                "level": batteryValue,
                "charging": charging,
                "low_power_mode": ProcessInfo.processInfo.isLowPowerModeEnabled
            ],
            "capability_flags": ["background_location": true]
        ]
        let event: [String: Any] = [
            "action_id": payload["action_id"]!,
            "expected_state": operationalState,
            "expected_versions": ["driver": driverVersion],
            "payload": payload
        ]
        var queue = SecureGpsQueue.shared.load(for: context.identity)
        queue.enqueue(event)
        SecureGpsQueue.shared.save(queue)
        flush()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        NotificationCenter.default.post(name: .init("MiseLocationWarning"), object: nil,
          userInfo: ["code": "location_error", "detail": error.localizedDescription])
    }

    private func permission() -> String {
        switch currentAuthorizationStatus() {
        case .authorizedAlways: return "always"
        case .authorizedWhenInUse: return "while_in_use"
        case .denied: return "denied"
        case .restricted: return "restricted"
        default: return "unknown"
        }
    }

    private func currentAuthorizationStatus() -> CLAuthorizationStatus {
        if #available(iOS 14.0, *) {
            return manager.authorizationStatus
        }
        return CLLocationManager.authorizationStatus()
    }

    private func flush() {
        precondition(Thread.isMainThread)
        guard let context = currentContext(), uploadRequestID == nil,
              session.authorizedSince != nil, policyEnabled, allowed.contains(operationalState),
              UIApplication.shared.applicationState == .active || backgroundPolicyEnabled,
              let event = SecureGpsQueue.shared.load(for: context.identity).events.first,
              let actionID = event["action_id"] as? String,
              let body = try? JSONSerialization.data(withJSONObject: event),
              let url = runtime.endpoint(path: "/api/driver/v2/gps/events") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(context.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let requestID = UUID()
        uploadRequestID = requestID
        uploadTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                guard let self, self.uploadRequestID == requestID,
                      self.currentContext() == context, self.session.matches(context) else { return }
                self.uploadTask = nil
                self.uploadRequestID = nil
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 401 || status == 403 { self.logout(); return }
                // Reload before mutation: captures made during the request must
                // survive both ACKs and retry bookkeeping. Never save a snapshot.
                var queue = SecureGpsQueue.shared.load(for: context.identity)
                if (200...299).contains(status) {
                    queue.acknowledge(actionID: actionID)
                    guard SecureGpsQueue.shared.save(queue) else {
                        self.apply(state: "offline", policyEnabled: false); return
                    }
                    self.retrySeconds = 1
                    self.flush()
                } else if (400...499).contains(status) && status != 429 {
                    self.quarantine("terminal_http_\(status)")
                    queue.acknowledge(actionID: actionID)
                    guard SecureGpsQueue.shared.save(queue) else {
                        self.apply(state: "offline", policyEnabled: false); return
                    }
                    self.retrySeconds = 1
                    self.apply(state: "offline", policyEnabled: false)
                    self.refreshServerAuthorization()
                } else {
                    guard let attempts = queue.incrementAttempts(actionID: actionID) else { self.flush(); return }
                    if attempts >= 6 {
                        self.quarantine("retry_exhausted")
                        queue.acknowledge(actionID: actionID)
                        guard SecureGpsQueue.shared.save(queue) else {
                            self.apply(state: "offline", policyEnabled: false); return
                        }
                        self.retrySeconds = 1
                        self.flush()
                        return
                    }
                    guard SecureGpsQueue.shared.save(queue) else {
                        self.apply(state: "offline", policyEnabled: false); return
                    }
                    let delay = self.retrySeconds
                    self.retrySeconds = min(self.retrySeconds * 2, 60)
                    let item = DispatchWorkItem { [weak self] in
                        guard let self, self.currentContext() == context,
                              self.session.matches(context) else { return }
                        self.flush()
                    }
                    self.retryWorkItem?.cancel()
                    self.retryWorkItem = item
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
                }
            }
        }
        uploadTask?.resume()
    }

    private func currentContext() -> GpsRequestContext? {
        precondition(Thread.isMainThread)
        guard runtime.operationsEnabled else { return nil }
        if let token = defaults.string(forKey: credentialHandoffKey) {
            defaults.removeObject(forKey: credentialHandoffKey)
            let previous = session.context
            session.accept(token: token)
            guard let next = session.context else { logout(); return nil }
            if next != previous {
                authorizationTask?.cancel()
                authorizationTask = nil
                authorizationRequestID = nil
                apply(state: "offline", policyEnabled: false)
                retrySeconds = 1
                if let previous, previous.identity != next.identity { SecureGpsQueue.shared.clearQueue() }
                // Also discard an old, unowned, or other-account queue on launch.
                _ = SecureGpsQueue.shared.load(for: next.identity)
            }
        }
        guard let context = session.context else { return nil }
        guard session.matches(context) else { logout(); return nil }
        return context
    }

    private func cancelUpload() {
        uploadTask?.cancel()
        uploadTask = nil
        uploadRequestID = nil
        retryWorkItem?.cancel()
        retryWorkItem = nil
    }

    private func quarantine(_ reason: String) {
        defaults.set(["reason": reason, "at": ISO8601DateFormatter().string(from: Date())],
                     forKey: "mise.gps.last_quarantine.v2")
    }

    private func deleteLegacyToken() {
        let identity: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
          kSecAttrService as String: "app.mise.driver", kSecAttrAccount as String: tokenAccount]
        SecItemDelete(identity as CFDictionary)
    }
}
