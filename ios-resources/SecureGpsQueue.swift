import CryptoKit
import Foundation
import Security

final class SecureGpsQueue {
    static let shared = SecureGpsQueue()
    private let account = "mise.driver.gps-queue-key.v2"
    private let legacyKey = "mise.gps.queue.v2"
    private let fileURL: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true,
          attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        fileURL = support.appendingPathComponent("gps-queue-v2.enc")
        migrateLegacyOnce()
    }

    func load() -> [[String: Any]] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let sealed = try Data(contentsOf: fileURL)
            let box = try AES.GCM.SealedBox(combined: sealed)
            let clear = try AES.GCM.open(box, using: key())
            return try JSONSerialization.jsonObject(with: clear) as? [[String: Any]] ?? []
        } catch {
            // Fail closed: remove unreadable coordinate material and retain
            // only non-sensitive operational metadata.
            try? FileManager.default.removeItem(at: fileURL)
            UserDefaults.standard.set([
              "reason": "secure_queue_corrupt",
              "at": ISO8601DateFormatter().string(from: Date())
            ], forKey: "mise.gps.last_quarantine.v2")
            return []
        }
    }

    @discardableResult
    func save(_ queue: [[String: Any]]) -> Bool {
        do {
            let bounded = Array(queue.suffix(100))
            let clear = try canonicalData(bounded)
            let sealed = try AES.GCM.seal(clear, using: key()).combined!
            try sealed.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try FileManager.default.setAttributes(
              [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
              ofItemAtPath: fileURL.path)
            return true
        } catch {
            UserDefaults.standard.set([
              "reason": "secure_queue_write_failed",
              "at": ISO8601DateFormatter().string(from: Date())
            ], forKey: "mise.gps.last_quarantine.v2")
            return false
        }
    }

    private func migrateLegacyOnce() {
        let defaults = UserDefaults.standard
        guard let legacy = defaults.array(forKey: legacyKey) as? [[String: Any]] else { return }
        let expected = Array(legacy.suffix(100))
        let persisted = save(expected)
        // Delete plaintext only if decrypting the stored ciphertext produces
        // the exact canonical bounded payload, not merely the same row count.
        let roundTrip = load()
        if persisted,
           let expectedData = try? canonicalData(expected),
           let roundTripData = try? canonicalData(roundTrip),
           expectedData == roundTripData {
            defaults.removeObject(forKey: legacyKey)
        }
    }

    private func canonicalData(_ queue: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: queue, options: [.sortedKeys])
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
