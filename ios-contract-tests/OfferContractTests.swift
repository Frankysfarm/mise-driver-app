import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

private func decodedBridgeDetail(_ script: String) -> [String: Any]? {
    guard let marker = script.range(of: "atob('"),
          let end = script[marker.upperBound...].firstIndex(of: "'")
    else {
        return nil
    }
    let encoded = String(script[marker.upperBound..<end])
    guard let data = Data(base64Encoded: encoded),
          let object = try? JSONSerialization.jsonObject(with: data)
    else {
        return nil
    }
    return object as? [String: Any]
}

let first = OfferEnvelope.parse([
    "offer_id": "offer-a",
    "batch_id": "batch-a",
    "assignment_version": 7,
])
require(first?.offerId == "offer-a", "explicit offer_id must survive parsing")
require(first?.batchId == "batch-a", "batch_id must survive parsing")
require(first?.assignmentVersion == 7, "numeric assignment version must normalize")
require(
    OfferEnvelope.parse(["batch_id": "batch-string-version", "assignment_version": "8"])?.assignmentVersion == 8,
    "numeric string assignment version must normalize to an integer"
)
require(
    OfferEnvelope.parse(["batch_id": "batch-fraction", "assignment_version": 1.5])?.assignmentVersion == nil,
    "fractional assignment version must be rejected"
)

let legacy = OfferEnvelope.parse(["batch_id": "batch-legacy"])
require(legacy?.offerId == "legacy-batch:batch-legacy", "legacy payload must have deterministic identity")
require(OfferEnvelope.parse(["offer_id": "orphan"]) == nil, "payload without batch_id must be rejected")

let suiteName = "mise.offer-contract-tests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suiteName)!
defer { defaults.removePersistentDomain(forName: suiteName) }
let registry = OfferRegistry(defaults: defaults, storageKey: "registry")
let firstId = UUID()
let secondId = UUID()
let second = OfferEnvelope(offerId: "offer-b", batchId: "batch-b", assignmentVersion: 8)
registry.insert(first!, for: firstId)
registry.insert(second, for: secondId)
require(registry.offer(for: firstId) == first, "first call must retain its own immutable offer")
require(registry.offer(for: secondId) == second, "second call must retain its own immutable offer")
let restoredRegistry = OfferRegistry(defaults: defaults, storageKey: "registry")
require(restoredRegistry.offer(for: firstId) == first, "call mapping must survive process recreation")
require(restoredRegistry.offer(for: secondId) == second, "all active calls must restore independently")
require(registry.remove(for: firstId) == first, "answer must remove and return the exact call offer")
require(registry.offer(for: secondId) == second, "answering first call must not change second")

let now = Date(timeIntervalSince1970: 1_000)
let bridgeEvent = OfferBridgeEvent(offer: second, stage: "answered", now: now, timeToLive: 60)
require(bridgeEvent.id == "offer-b|batch-b|8|answered", "bridge identity must include assignment version")
let nextVersion = OfferBridgeEvent(
    offer: OfferEnvelope(offerId: "offer-b", batchId: "batch-b", assignmentVersion: 9),
    stage: "answered",
    now: now
)
require(nextVersion.id != bridgeEvent.id, "new assignment version must never dedupe with stale event")
require(!bridgeEvent.isExpired(at: now.addingTimeInterval(59)), "event must remain before TTL")
require(bridgeEvent.isExpired(at: now.addingTimeInterval(60)), "event must expire at TTL")
let roundTrip = try! JSONDecoder().decode(
    OfferBridgeEvent.self,
    from: JSONEncoder().encode(bridgeEvent)
)
require(roundTrip == bridgeEvent, "queued bridge event must survive process restart")

let bridgeQueue = OfferBridgeQueue(defaults: defaults, storageKey: "bridge", capacity: 3)
bridgeQueue.enqueue(bridgeEvent, now: now)
bridgeQueue.enqueue(bridgeEvent, now: now)
require(bridgeQueue.activeEvents(at: now).count == 1, "duplicate event must be queued once")
let restoredQueue = OfferBridgeQueue(defaults: defaults, storageKey: "bridge", capacity: 3)
require(restoredQueue.activeEvents(at: now) == [bridgeEvent], "bridge queue must survive process recreation")
require(restoredQueue.acknowledge(eventId: bridgeEvent.id, now: now), "explicit ACK must remove known event")
require(restoredQueue.activeEvents(at: now).isEmpty, "ACKed event must not replay")
bridgeQueue.enqueue(bridgeEvent, now: now)
require(bridgeQueue.activeEvents(at: now.addingTimeInterval(60)).isEmpty, "expired event must not replay")

let hostile = OfferEnvelope(offerId: "x');alert(1)//", batchId: "batch", assignmentVersion: nil)
let hostileEvent = OfferBridgeEvent(offer: hostile, stage: "opened", now: now)
let script = hostileEvent.bridgeJavaScript()
require(script != nil, "bridge script must serialize")
require(!script!.contains("alert(1)"), "payload must not be interpolated into executable JavaScript")
let decoded = decodedBridgeDetail(script!)
require(decoded?["offer_id"] as? String == hostile.offerId, "encoded bridge must preserve exact top-level offer")
require(decoded?["batch_id"] as? String == hostile.batchId, "encoded bridge must preserve top-level batch")
require(decoded?["event_id"] as? String == hostileEvent.id, "bridge must expose explicit ACK identity")
require((decoded?["ack_url"] as? String)?.hasPrefix("mise-driver://offer-ack?") == true, "bridge must expose native ACK URL")
require(decoded?["offer"] == nil, "canonical bridge payload must not emit a nested offer object")

require(TokenRetryPolicy.shouldRetry(statusCode: nil), "network failures must retry")
require(TokenRetryPolicy.shouldRetry(statusCode: 500), "server failures must retry")
require(!TokenRetryPolicy.shouldRetry(statusCode: 401), "auth failure must wait for reconciliation")
require(TokenRetryPolicy.delay(attempt: 20, jitterUnit: 1) <= TokenRetryPolicy.maximumDelay, "retry must be capped")
require(
    TokenRetryPolicy.completionAction(
        attemptedToken: "old",
        newestToken: "new",
        attempt: 2,
        statusCode: 200,
        hadNetworkError: false
    ) == .superseded,
    "newest token must win even when old upload succeeds"
)
require(
    TokenRetryPolicy.completionAction(
        attemptedToken: "same",
        newestToken: "same",
        attempt: 2,
        statusCode: 500,
        hadNetworkError: false
    ) == .retry(nextAttempt: 3),
    "transient completion must advance retry state"
)
require(
    TokenRetryPolicy.completionAction(
        attemptedToken: "same",
        newestToken: "same",
        attempt: 2,
        statusCode: 401,
        hadNetworkError: false
    ) == .awaitAuthChange,
    "auth failure must retain state for explicit auth reconciliation"
)

require(BridgeReplayPolicy.delay(attempt: 0) == 1, "first replay must be prompt")
require(BridgeReplayPolicy.delay(attempt: 1) == 3, "replay must back off")
require(BridgeReplayPolicy.delay(attempt: 3) == 30, "last bounded replay must remain finite")
require(BridgeReplayPolicy.delay(attempt: 4) == nil, "replay must stop instead of busy-looping")
require(BridgeReplayPolicy.delay(attempt: -1) == nil, "invalid replay attempt must stop")

print("PASS: OfferContractTests")
