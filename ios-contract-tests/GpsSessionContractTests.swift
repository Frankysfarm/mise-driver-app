import Foundation

var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
let now = Date(timeIntervalSince1970: 1_800_000_000)
func token(subject: String = "driver-a", issuer: String = "https://auth.example.test", expires: Double = 1_800_003_600) -> String {
    let claims: [String: Any] = ["iss": issuer, "sub": subject, "exp": expires]
    let data = try! JSONSerialization.data(withJSONObject: claims, options: [.sortedKeys])
    let base64 = data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    return "header.\(base64).signature"
}
func event(_ id: String, second: Int = 0) -> [String: Any] {
    ["action_id": id, "payload": ["captured_at": String(format: "2026-10-02T10:%02d:%02dZ", second / 60, second % 60),
                                  "latitude": 50.0, "longitude": 8.0, "heading_deg": NSNull()]]
}
let accessA = token()
let ownerA = GpsIdentity.parse(token: accessA, now: now)!
let ownerB = GpsIdentity.parse(token: token(subject: "driver-b"), now: now)!
expect(GpsIdentity.parse(token: "broken", now: now) == nil, "Malformed token must fail closed")
expect(GpsIdentity.parse(token: token(subject: ""), now: now) == nil, "Missing subject must fail closed")
expect(GpsIdentity.parse(token: token(issuer: " "), now: now) == nil, "Missing issuer must fail closed")
expect(GpsIdentity.parse(token: token(expires: now.timeIntervalSince1970), now: now) == nil, "Expired token rejected at boundary")
expect(ownerA != ownerB, "Subject changes queue owner")
expect(ownerA != GpsIdentity.parse(token: token(issuer: "https://other-auth.test"), now: now), "Issuer changes queue owner")

var session = GpsSessionState()
session.accept(token: accessA, now: now)
let requestA = session.context!
expect(session.authorizedSince == nil, "Decoded JWT alone must not authorize collection")
expect(!session.permitsCapture(at: now, context: requestA, now: now), "No capture before authenticated server response")
expect(session.authorize(requestA, now: now), "Current server response authorizes current identity")
expect(session.permitsCapture(at: now, context: requestA, now: now), "Authorized fresh capture accepted")
expect(!session.permitsCapture(at: now.addingTimeInterval(-1), context: requestA, now: now), "Cached previous-session fix rejected")
expect(!session.permitsCapture(at: now.addingTimeInterval(30), context: requestA, now: now), "Implausibly future capture rejected")
session.accept(token: accessA, now: now)
expect(session.context == requestA && session.authorizedSince == now, "Repeated same-token heartbeat preserves current authorization")

// An in-flight snapshot/POST/retry from A must not affect B, even if A's
// callback arrives after B has received its successful server response.
session.accept(token: token(subject: "driver-b"), now: now)
let requestB = session.context!
expect(session.authorizedSince == nil, "Account switch needs fresh server authorization")
expect(!session.matches(requestA, now: now), "Old upload/retry context rejected after account switch")
expect(!session.authorize(requestA, now: now), "Stale snapshot cannot authorize new account")
expect(session.authorize(requestB, now: now), "New account snapshot accepted")
expect(!session.authorize(requestA, now: now) && session.context == requestB, "Late A snapshot cannot replace authorized B")

session.invalidate()
expect(session.context == nil && session.authorizedSince == nil, "Logout clears identity and authority")
expect(!session.matches(requestB, now: now), "Outstanding POST/retry invalidated by logout")
expect(!session.authorize(requestB, now: now), "Signed-out callback cannot restart tracking")
session.accept(token: token(subject: "driver-b"), now: now)
let relogin = session.context!
expect(relogin.generation != requestB.generation, "Same-account relogin creates a distinct generation")
expect(!session.authorize(requestB, now: now), "Pre-logout callback rejected after same-account relogin")
expect(session.authorize(relogin, now: now), "Relogin needs its own server response")
session.suspend()
expect(!session.permitsCapture(at: now, context: relogin, now: now), "Network/policy suspension stops capture")
session.accept(token: token(subject: "driver-b", expires: 1_800_007_200), now: now)
let rotated = session.context!
expect(rotated.identity == relogin.identity && rotated.generation != relogin.generation, "Token rotation keeps owner but invalidates old callbacks")
expect(!session.matches(relogin, now: now), "Old token callback rejected after refresh")
expect(!session.matches(rotated, now: Date(timeIntervalSince1970: 1_800_007_200)), "Expired current credential invalidates callbacks")
session.accept(token: "invalid", now: now)
expect(session.context == nil && session.authorizedSince == nil, "Invalid handoff revokes current authorization")

var queue = GpsQueueEnvelope(owner: ownerA)
queue.enqueue(event("sent"))
let sentID = queue.events[0]["action_id"] as! String
queue.enqueue(event("during-upload", second: 1))
queue.acknowledge(actionID: sentID)
expect(queue.events.count == 1 && queue.events[0]["action_id"] as? String == "during-upload", "ACK preserves points enqueued during upload")
queue.acknowledge(actionID: sentID)
expect(queue.events.count == 1, "Duplicate ACK cannot remove the next event")
queue.enqueue(event("later", second: 2))
expect(queue.incrementAttempts(actionID: "during-upload") == 1, "Retry updates original event")
expect(queue.events.count == 2, "Retry bookkeeping preserves concurrent enqueue")
expect(queue.events[1]["transport_attempts"] == nil, "Retry never increments a different event")
expect(queue.incrementAttempts(actionID: "missing") == nil && queue.events.count == 2, "Stale retry for removed event leaves current queue intact")
let encoded = try! JSONSerialization.data(withJSONObject: queue.storage)
let stored = try! JSONSerialization.jsonObject(with: encoded)
expect(GpsQueueEnvelope(stored: stored, owner: ownerA)?.events.count == 2, "Scoped queue roundtrip preserves GPS including JSON nulls")
expect(GpsQueueEnvelope(stored: stored, owner: ownerB) == nil, "Different account cannot adopt encrypted queue")
expect(GpsQueueEnvelope(stored: [event("legacy")], owner: ownerA) == nil, "Legacy unowned queue cannot adopt current account")
expect(GpsQueueEnvelope(stored: ["version": 3, "events": [event("unowned")]], owner: ownerA) == nil, "Missing owner is rejected")
for index in 0..<105 { queue.enqueue(event("bounded-\(index)", second: index + 3)) }
expect(queue.events.count == 100 && queue.events.last?["action_id"] as? String == "bounded-104", "Offline queue bounded to newest 100 points")
queue.enqueue(event("bounded-104", second: 107))
expect(queue.events.count == 100, "Repeated action ID is deduplicated")

let server = URL(string: "https://mise-gastro.de")!
func signedOut(_ address: String) -> Bool { GpsWebSessionNavigation.isSignedOut(URL(string: address)!, serverURL: server) }
expect(signedOut("https://mise-gastro.de/fahrer"), "Existing logout destination revokes GPS")
expect(signedOut("https://mise-gastro.de/fahrer/login/?next=app"), "Login destination with slash/query revokes GPS")
expect(!signedOut("https://mise-gastro.de/fahrer/app"), "Authenticated driver application keeps its session")
expect(!signedOut("https://mise-gastro.de/fahrer/login-help"), "Only exact signed-out paths revoke")
expect(!signedOut("https://other.example/fahrer"), "Unrelated origin does not control session state")
expect(!signedOut("http://mise-gastro.de/fahrer"), "Insecure origin does not match configured server")
expect(!signedOut("https://mise-gastro.de:8443/fahrer"), "Different origin port does not match")
print("GPS session contract tests: \(checks) passed")
