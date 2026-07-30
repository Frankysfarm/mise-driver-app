import CoreLocation
import Foundation
import Security
import UIKit

final class LocationTracking: NSObject, CLLocationManagerDelegate {
    static let shared = LocationTracking()
    private let manager = CLLocationManager()
    private let defaults = UserDefaults.standard
    private let sequenceKey = "mise.gps.sequence.v2"
    private let sessionKey = "mise.gps.session.v2"
    private let installationKey = "mise.gps.installation.v2"
    private let allowed = Set(["available", "assigned", "at_pickup", "delivering", "returning"])
    private(set) var operationalState = "offline"
    private(set) var policyEnabled = false
    private(set) var driverVersion = 0
    private(set) var backgroundPolicyEnabled = false
    private var uploadInFlight = false
    private var retrySeconds: TimeInterval = 1
    private let tokenAccount = "mise.driver.access-token"

    override private init() {
        super.init()
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
        let authorityChanged = operationalState != state || self.driverVersion != driverVersion
        self.operationalState = state
        self.driverVersion = driverVersion
        self.policyEnabled = policyEnabled
        self.backgroundPolicyEnabled = backgroundPolicyEnabled
        if authorityChanged {
            defaults.set(UUID().uuidString.lowercased(), forKey: sessionKey)
            defaults.set(0, forKey: sequenceKey)
        }
        guard policyEnabled && allowed.contains(state) else {
            manager.stopUpdatingLocation()
            manager.stopMonitoringSignificantLocationChanges()
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
        guard let access = secureAccessToken(),
              let url = URL(string: "https://mise-gastro.de/api/driver/v2/snapshot") else {
            apply(state: "offline", policyEnabled: false); return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self, (response as? HTTPURLResponse)?.statusCode == 200,
                  let data, let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let snapshot = root["snapshot"] as? [String: Any],
                  let driver = snapshot["driver"] as? [String: Any],
                  let gps = snapshot["gps_transport"] as? [String: Any] else {
                DispatchQueue.main.async { self?.apply(state: "offline", policyEnabled: false) }; return
            }
            let state = driver["state"] as? String ?? "offline"
            let version = driver["version"] as? Int ?? 0
            let enabled = gps["policy_enabled"] as? Bool ?? false
            let background = gps["background_policy_enabled"] as? Bool ?? false
            DispatchQueue.main.async { self.apply(state: state, driverVersion: version, policyEnabled: enabled, backgroundPolicyEnabled: background) }
        }.resume()
    }

    func enteredBackground() {
        if !backgroundPolicyEnabled {
            manager.stopUpdatingLocation()
            manager.stopMonitoringSignificantLocationChanges()
        } else {
            refreshServerAuthorization()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard policyEnabled && allowed.contains(operationalState), let location = locations.last else { return }
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
        enqueue(event); flush()
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

    private func enqueue(_ event: [String: Any]) {
        var queue = SecureGpsQueue.shared.load()
        queue.removeAll { ($0["action_id"] as? String) == (event["action_id"] as? String) }
        queue.append(event)
        queue.sort {
            let left = (($0["payload"] as? [String: Any])?["captured_at"] as? String) ?? ""
            let right = (($1["payload"] as? [String: Any])?["captured_at"] as? String) ?? ""
            return left < right
        }
        if PropertyListSerialization.propertyList(queue, isValidFor: .binary) {
            SecureGpsQueue.shared.save(Array(queue.suffix(100)))
        }
    }

    private func flush() {
        guard !uploadInFlight else { return }
        guard let access = secureAccessToken(),
              var queue = Optional(SecureGpsQueue.shared.load()), let event = queue.first,
              let url = URL(string: "https://mise-gastro.de/api/driver/v2/gps/events") else { return }
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: event)
        uploadInFlight = true
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            DispatchQueue.main.async {
                self.uploadInFlight = false
                if (200...299).contains(status) {
                    queue.removeFirst(); SecureGpsQueue.shared.save(queue)
                    self.retrySeconds = 1
                    if !queue.isEmpty { self.flush() }
                } else if status == 409 || (400...499).contains(status) && status != 429 {
                    // Canonical conflicts/invalid envelopes are terminal for
                    // this immutable head. Quarantine metadata only, discard
                    // coordinates, reauthorize, then allow later points.
                    let reason = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["reason_code"] as? String ?? "terminal_http_\(status)"
                    self.defaults.set(["reason": reason, "at": ISO8601DateFormatter().string(from: Date())], forKey: "mise.gps.last_quarantine.v2")
                    queue.removeFirst(); SecureGpsQueue.shared.save(queue)
                    self.refreshServerAuthorization()
                    self.retrySeconds = 1
                    if !queue.isEmpty { self.flush() }
                } else {
                    var head=queue[0]
                    let attempts=(head["transport_attempts"] as? Int ?? 0)+1
                    if attempts >= 6 {
                        self.defaults.set(["reason":"retry_exhausted","at":ISO8601DateFormatter().string(from:Date())],forKey:"mise.gps.last_quarantine.v2")
                        queue.removeFirst(); SecureGpsQueue.shared.save(queue)
                        self.retrySeconds=1
                        if !queue.isEmpty { self.flush() }
                        return
                    }
                    head["transport_attempts"]=attempts
                    queue[0]=head; SecureGpsQueue.shared.save(queue)
                    let delay = self.retrySeconds
                    self.retrySeconds = min(self.retrySeconds * 2, 60)
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.flush() }
                }
            }
        }.resume()
    }

    private func secureAccessToken() -> String? {
        if let legacy=defaults.string(forKey:"CapacitorStorage.mise_access_token"),
           let data=legacy.data(using:.utf8) {
            let identity: [String:Any] = [kSecClass as String:kSecClassGenericPassword,
              kSecAttrService as String:"app.mise.driver",kSecAttrAccount as String:tokenAccount]
            let status=SecItemUpdate(identity as CFDictionary,[kSecValueData as String:data] as CFDictionary)
            if status == errSecItemNotFound {
                var add=identity; add[kSecValueData as String]=data
                add[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                SecItemAdd(add as CFDictionary,nil)
            }
            defaults.removeObject(forKey:"CapacitorStorage.mise_access_token")
            return legacy
        }
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,
          kSecAttrService as String:"app.mise.driver", kSecAttrAccount as String:tokenAccount,
          kSecReturnData as String:true]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data=item as? Data, let token=String(data:data,encoding:.utf8) { return token }
        return nil
    }
}
