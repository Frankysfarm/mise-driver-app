import Foundation

// Bundle identity and signed build metadata determine native capability gates.
// The Frankys canary cannot be enabled by a web page or runtime token handoff.
struct DriverRuntimeConfiguration {
    let urlScheme: String?
    let operationsEnabled: Bool

    static var current: DriverRuntimeConfiguration {
        DriverRuntimeConfiguration(bundleIdentifier: Bundle.main.bundleIdentifier,
                                   info: Bundle.main.infoDictionary ?? [:])
    }

    init(bundleIdentifier: String?, info: [String: Any]) {
        let legacyMise = bundleIdentifier == "app.mise.driver"
        let expectedScheme: String?
        switch bundleIdentifier {
        case "app.mise.driver": expectedScheme = "mise-driver"
        case "de.frankysfarm.driver": expectedScheme = "frankys-driver"
        default: expectedScheme = nil
        }
        let declaredID = info["DriverExpectedBundleIdentifier"] as? String
        let declaredScheme = info["DriverURLScheme"] as? String
        let identityMatches = expectedScheme != nil
            && (declaredID == bundleIdentifier || legacyMise && declaredID == nil)
            && (declaredScheme == expectedScheme || legacyMise && declaredScheme == nil)
        urlScheme = identityMatches ? expectedScheme : nil
        // Missing keys preserve only the original Mise app. Unknown bundles,
        // mismatched metadata and the installation-only variant fail closed.
        operationsEnabled = legacyMise && identityMatches
            && (info["DriverOperationsEnabled"] == nil || info["DriverOperationsEnabled"] as? Bool == true)
            && info["DriverInstallationCanary"] as? Bool != true
    }
}

// JWT claims only partition local data. Only a successful authenticated server
// snapshot grants GPS authorization; decoding a token never grants it.
struct GpsIdentity: Equatable {
    let issuer: String
    let subject: String

    static func parse(token: String, now: Date = Date()) -> GpsIdentity? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let issuer = claims["iss"] as? String, !issuer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let subject = claims["sub"] as? String, !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let expires = claims["exp"] as? Double, expires.isFinite,
              expires > now.timeIntervalSince1970 else { return nil }
        return GpsIdentity(issuer: issuer, subject: subject)
    }
}

struct GpsRequestContext: Equatable {
    let generation: UUID
    let identity: GpsIdentity
    let token: String
}

struct GpsSessionState {
    private(set) var context: GpsRequestContext?
    private(set) var authorizedSince: Date?

    mutating func accept(token: String, now: Date = Date()) {
        guard let identity = GpsIdentity.parse(token: token, now: now) else { invalidate(); return }
        guard context?.token != token else { return }
        context = GpsRequestContext(generation: UUID(), identity: identity, token: token)
        authorizedSince = nil
    }

    func matches(_ candidate: GpsRequestContext, now: Date = Date()) -> Bool {
        context == candidate && GpsIdentity.parse(token: candidate.token, now: now) == candidate.identity
    }

    @discardableResult
    mutating func authorize(_ candidate: GpsRequestContext, now: Date = Date()) -> Bool {
        guard matches(candidate, now: now) else { return false }
        if authorizedSince == nil { authorizedSince = now }
        return true
    }

    mutating func suspend() { authorizedSince = nil }
    mutating func invalidate() { context = nil; authorizedSince = nil }

    func permitsCapture(at timestamp: Date, context: GpsRequestContext, now: Date = Date()) -> Bool {
        guard matches(context, now: now), let authorizedSince else { return false }
        // CLLocation may replay an earlier account's cached fix after a restart.
        return timestamp >= authorizedSince && timestamp <= now.addingTimeInterval(10)
    }
}

enum GpsWebSessionNavigation {
    static func isSignedOut(_ url: URL, serverURL: URL) -> Bool {
        guard url.scheme == serverURL.scheme, url.host == serverURL.host,
              url.port == serverURL.port else { return false }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path == "fahrer" || path == "fahrer/login"
    }
}

struct GpsQueueEnvelope {
    let owner: GpsIdentity
    private(set) var events: [[String: Any]]

    init(owner: GpsIdentity, events: [[String: Any]] = []) {
        self.owner = owner
        self.events = Array(events.suffix(100))
    }

    init?(stored: Any, owner: GpsIdentity) {
        guard let envelope = stored as? [String: Any], envelope["version"] as? Int == 3,
              let identity = envelope["owner"] as? [String: String],
              identity["issuer"] == owner.issuer, identity["subject"] == owner.subject,
              let events = envelope["events"] as? [[String: Any]] else { return nil }
        self.init(owner: owner, events: events)
    }

    var storage: [String: Any] {
        ["version": 3, "owner": ["issuer": owner.issuer, "subject": owner.subject], "events": events]
    }

    mutating func enqueue(_ event: [String: Any]) {
        guard let actionID = event["action_id"] as? String, !actionID.isEmpty,
              JSONSerialization.isValidJSONObject(event) else { return }
        acknowledge(actionID: actionID)
        events.append(event)
        events.sort {
            let left = (($0["payload"] as? [String: Any])?["captured_at"] as? String) ?? ""
            let right = (($1["payload"] as? [String: Any])?["captured_at"] as? String) ?? ""
            return left < right
        }
        events = Array(events.suffix(100))
    }

    mutating func acknowledge(actionID: String) {
        events.removeAll { $0["action_id"] as? String == actionID }
    }

    mutating func incrementAttempts(actionID: String) -> Int? {
        guard let index = events.firstIndex(where: { $0["action_id"] as? String == actionID }) else { return nil }
        let attempts = (events[index]["transport_attempts"] as? Int ?? 0) + 1
        events[index]["transport_attempts"] = attempts
        return attempts
    }
}

#if os(iOS)
import CryptoKit
import Security

// All queue mutations run on LocationTracking's main-thread state machine.
final class SecureGpsQueue {
    static let shared = SecureGpsQueue()
    private let account = "mise.driver.gps-queue-key.v2"
    private let fileURL: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true,
          attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        fileURL = support.appendingPathComponent("gps-queue-v2.enc")
        // Old plaintext queues have no provable owner. Never assign their
        // coordinates to whichever account happens to sign in after upgrading.
        UserDefaults.standard.removeObject(forKey: "mise.gps.queue.v2")
    }

    func load(for owner: GpsIdentity) -> GpsQueueEnvelope {
        precondition(Thread.isMainThread)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return GpsQueueEnvelope(owner: owner) }
        do {
            let sealed = try Data(contentsOf: fileURL)
            let box = try AES.GCM.SealedBox(combined: sealed)
            let clear = try AES.GCM.open(box, using: key())
            let stored = try JSONSerialization.jsonObject(with: clear)
            guard let queue = GpsQueueEnvelope(stored: stored, owner: owner) else {
                clearQueue()
                quarantine("secure_queue_unowned_or_other_identity")
                return GpsQueueEnvelope(owner: owner)
            }
            return queue
        } catch {
            clearQueue()
            quarantine("secure_queue_corrupt")
            return GpsQueueEnvelope(owner: owner)
        }
    }

    @discardableResult
    func save(_ queue: GpsQueueEnvelope) -> Bool {
        precondition(Thread.isMainThread)
        do {
            let clear = try JSONSerialization.data(withJSONObject: queue.storage, options: [.sortedKeys])
            let sealed = try AES.GCM.seal(clear, using: key()).combined!
            try sealed.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try FileManager.default.setAttributes(
              [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: fileURL.path)
            return true
        } catch {
            quarantine("secure_queue_write_failed")
            return false
        }
    }

    func clearQueue() {
        precondition(Thread.isMainThread)
        try? FileManager.default.removeItem(at: fileURL)
        UserDefaults.standard.removeObject(forKey: "mise.gps.queue.v2")
    }

    private func quarantine(_ reason: String) {
        UserDefaults.standard.set(["reason": reason, "at": ISO8601DateFormatter().string(from: Date())],
                                  forKey: "mise.gps.last_quarantine.v2")
    }

    private func key() throws -> SymmetricKey {
        let identity: [String: Any] = [
          kSecClass as String: kSecClassGenericPassword,
          kSecAttrService as String: "app.mise.driver",
          kSecAttrAccount as String: account
        ]
        var query = identity
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data { return SymmetricKey(data: data) }
        let data = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        var add = identity
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else {
            throw NSError(domain: "SecureGpsQueue", code: 1)
        }
        return SymmetricKey(data: data)
    }
}
#endif
