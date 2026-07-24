import Foundation

let offer = OfferEnvelope(
    offerId: "fixture-offer",
    batchId: "fixture-batch",
    assignmentVersion: 7
)
let event = OfferBridgeEvent(
    offer: offer,
    stage: "opened",
    now: Date(timeIntervalSince1970: 1_000),
    timeToLive: 60
)
guard let payload = event.bridgePayload(),
      JSONSerialization.isValidJSONObject(payload),
      let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
else {
    FileHandle.standardError.write(Data("failed to emit native fixture\n".utf8))
    exit(1)
}
FileHandle.standardOutput.write(data)
