import Foundation

struct OfferEnvelope: Codable, Equatable {
    let offerId: String
    let batchId: String
    let assignmentVersion: Int?

    static func parse(_ payload: [AnyHashable: Any]) -> OfferEnvelope? {
        guard let batchId = normalizedString(payload["batch_id"]), !batchId.isEmpty else {
            return nil
        }
        let explicitOfferId = normalizedString(payload["offer_id"])
            ?? normalizedString(payload["decision_id"])
        return OfferEnvelope(
            offerId: explicitOfferId?.isEmpty == false ? explicitOfferId! : "legacy-batch:\(batchId)",
            batchId: batchId,
            assignmentVersion: normalizedPositiveInt(payload["assignment_version"])
        )
    }

    var bridgeDetail: [String: Any] {
        var detail: [String: Any] = [
            "offer_id": offerId,
            "batch_id": batchId,
        ]
        if let assignmentVersion {
            detail["assignment_version"] = assignmentVersion
        }
        return detail
    }

    private static func normalizedString(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func normalizedPositiveInt(_ value: Any?) -> Int? {
        let parsed: Int?
        switch value {
        case let number as NSNumber:
            let double = number.doubleValue
            parsed = double.rounded() == double ? number.intValue : nil
        case let string as String:
            parsed = Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            parsed = nil
        }
        guard let parsed, parsed > 0 else { return nil }
        return parsed
    }
}

struct OfferBridgeEvent: Codable, Equatable {
    let offer: OfferEnvelope
    let stage: String
    let createdAt: Date
    let expiresAt: Date

    var id: String {
        let version = offer.assignmentVersion.map(String.init) ?? "none"
        return "\(offer.offerId)|\(offer.batchId)|\(version)|\(stage)"
    }

    init(offer: OfferEnvelope, stage: String, now: Date = Date(), timeToLive: TimeInterval = 24 * 60 * 60) {
        self.offer = offer
        self.stage = stage
        self.createdAt = now
        self.expiresAt = now.addingTimeInterval(timeToLive)
    }

    func isExpired(at now: Date = Date()) -> Bool {
        expiresAt <= now
    }

    func bridgeJavaScript() -> String? {
        guard let detail = bridgePayload() else { return nil }
        guard JSONSerialization.isValidJSONObject(detail),
              let data = try? JSONSerialization.data(withJSONObject: detail),
              let json = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        // Evaluation is transport only. The web app must explicitly call
        // MiseDriverNativeBridge.ack(detail) after it has consumed the event.
        let encoded = Data(json.utf8).base64EncodedString()
        return """
        (() => {
          const detail = JSON.parse(atob('\(encoded)'));
          window.MiseDriverNativeBridge = window.MiseDriverNativeBridge || {};
          window.MiseDriverNativeBridge.ack = (eventDetail) => {
            if (eventDetail && eventDetail.ack_url) window.location.href = eventDetail.ack_url;
          };
          window.dispatchEvent(new CustomEvent('mise-driver-offer', { detail }));
        })();
        """
    }

    func bridgePayload() -> [String: Any]? {
        var detail = offer.bridgeDetail
        detail.merge([
            "event_id": id,
            "stage": stage,
        ]) { _, new in new }
        var components = URLComponents()
        components.scheme = "mise-driver"
        components.host = "offer-ack"
        components.queryItems = [URLQueryItem(name: "event_id", value: id)]
        if let ackURL = components.url?.absoluteString {
            detail["ack_url"] = ackURL
        }
        return detail
    }
}

final class OfferBridgeQueue {
    private let defaults: UserDefaults
    private let storageKey: String
    private let capacity: Int

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "mise_offer_bridge_pending_v2",
        capacity: Int = 20
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.capacity = max(1, capacity)
    }

    func enqueue(_ event: OfferBridgeEvent, now: Date = Date()) {
        var events = activeEvents(at: now)
        guard !events.contains(where: { $0.id == event.id }) else { return }
        events.append(event)
        if events.count > capacity {
            events.removeFirst(events.count - capacity)
        }
        persist(events)
    }

    func activeEvents(at now: Date = Date()) -> [OfferBridgeEvent] {
        let decoded = load().filter { !$0.isExpired(at: now) }
        persist(decoded)
        return decoded
    }

    @discardableResult
    func acknowledge(eventId: String, now: Date = Date()) -> Bool {
        let events = activeEvents(at: now)
        let existed = events.contains(where: { $0.id == eventId })
        persist(events.filter { $0.id != eventId })
        return existed
    }

    private func load() -> [OfferBridgeEvent] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([OfferBridgeEvent].self, from: data)) ?? []
    }

    private func persist(_ events: [OfferBridgeEvent]) {
        if events.isEmpty {
            defaults.removeObject(forKey: storageKey)
        } else if let data = try? JSONEncoder().encode(events) {
            defaults.set(data, forKey: storageKey)
        }
    }
}

final class OfferRegistry {
    private let defaults: UserDefaults
    private let storageKey: String
    private var offersByCallId: [UUID: OfferEnvelope] = [:]

    init(defaults: UserDefaults = .standard, storageKey: String = "mise_call_offer_registry_v1") {
        self.defaults = defaults
        self.storageKey = storageKey
        if let data = defaults.data(forKey: storageKey),
           let persisted = try? JSONDecoder().decode([String: OfferEnvelope].self, from: data) {
            offersByCallId = Dictionary(
                uniqueKeysWithValues: persisted.compactMap { key, value in
                    UUID(uuidString: key).map { ($0, value) }
                }
            )
        }
    }

    func insert(_ offer: OfferEnvelope, for callId: UUID) {
        offersByCallId[callId] = offer
        persist()
    }

    func offer(for callId: UUID) -> OfferEnvelope? {
        offersByCallId[callId]
    }

    @discardableResult
    func remove(for callId: UUID) -> OfferEnvelope? {
        let removed = offersByCallId.removeValue(forKey: callId)
        persist()
        return removed
    }

    func removeAll() {
        offersByCallId.removeAll()
        persist()
    }

    private func persist() {
        guard !offersByCallId.isEmpty else {
            defaults.removeObject(forKey: storageKey)
            return
        }
        let value = Dictionary(uniqueKeysWithValues: offersByCallId.map { ($0.key.uuidString, $0.value) })
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: storageKey)
        }
    }
}

enum TokenUploadCompletionAction: Equatable {
    case synced
    case retry(nextAttempt: Int)
    case awaitAuthChange
    case superseded
}

enum TokenRetryPolicy {
    static let maximumDelay: TimeInterval = 15 * 60

    static func delay(attempt: Int, jitterUnit: Double) -> TimeInterval {
        let safeAttempt = max(0, min(attempt, 10))
        let base = min(maximumDelay, 5 * pow(2, Double(safeAttempt)))
        let boundedJitter = max(0, min(jitterUnit, 1))
        return min(maximumDelay, base * (0.8 + boundedJitter * 0.4))
    }

    static func shouldRetry(statusCode: Int?) -> Bool {
        guard let statusCode else { return true }
        return statusCode == 408 || statusCode == 425 || statusCode == 429 || statusCode >= 500
    }

    static func completionAction(
        attemptedToken: String,
        newestToken: String?,
        attempt: Int,
        statusCode: Int?,
        hadNetworkError: Bool
    ) -> TokenUploadCompletionAction {
        if let newestToken, newestToken != attemptedToken {
            return .superseded
        }
        if !hadNetworkError, let statusCode, (200..<300).contains(statusCode) {
            return .synced
        }
        if hadNetworkError || shouldRetry(statusCode: statusCode) {
            return .retry(nextAttempt: attempt + 1)
        }
        return .awaitAuthChange
    }
}

enum BridgeReplayPolicy {
    private static let delays: [TimeInterval] = [1, 3, 10, 30]

    static func delay(attempt: Int) -> TimeInterval? {
        guard attempt >= 0, attempt < delays.count else { return nil }
        return delays[attempt]
    }
}
