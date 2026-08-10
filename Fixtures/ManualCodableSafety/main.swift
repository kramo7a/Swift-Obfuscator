import Foundation

struct ManualPayload: Codable {
    var value: Int = 0

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decode(Int.self, forKey: .value)
    }
}

let payload = try JSONDecoder().decode(ManualPayload.self, from: Data(#"{"value":7}"#.utf8))
precondition(payload.value == 7)
