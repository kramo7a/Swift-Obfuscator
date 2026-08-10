import Foundation

struct Envelope {
    struct MemberwisePayload: Codable {
        let serverName: String
        let retryCount: Int

        var diagnosticText: String {
            "\(serverName):\(retryCount)"
        }
    }
}

struct ExplicitPayload {
    let storedValue: Int

    init(externalLabel localValue: Int) {
        storedValue = localValue
    }
}

let memberwise = Envelope.MemberwisePayload(serverName: "alpha", retryCount: 3)
let encoded = try JSONEncoder().encode(memberwise)
let json = String(decoding: encoded, as: UTF8.self)
precondition(json.contains("\"serverName\":\"alpha\""))
precondition(json.contains("\"retryCount\":3"))
let decoded = try JSONDecoder().decode(Envelope.MemberwisePayload.self, from: encoded)
precondition(decoded.serverName == "alpha")
precondition(decoded.retryCount == 3)
precondition(decoded.diagnosticText == "alpha:3")

let explicit = ExplicitPayload(externalLabel: 4)
precondition(explicit.storedValue == 4)

@propertyWrapper
struct FixtureBox<Value> {
    var wrappedValue: Value
    var projectedValue: Value { wrappedValue }
}

struct WrapperOwner {
    @FixtureBox var wrappedNumber = 5
    var projectedNumber: Int { $wrappedNumber }
}

let wrapperOwner = WrapperOwner()
precondition(wrapperOwner.wrappedNumber == 5)
precondition(wrapperOwner.projectedNumber == 5)
