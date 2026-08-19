import Foundation
struct Payload: Codable, Equatable {
    let value: Int
    let other: Int
    let equal: Int
    enum CodingKeys: String, CodingKey {
        case value = "wire_value"
        case other
        case equal = "equal"
    }
}
let original = Payload(value: 7, other: 8, equal: 9)
let data = try JSONEncoder().encode(original)
let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
let otherKey = "other"
let equalKey = "equal"
precondition(object["wire_value"] as? Int == 7)
precondition(object[otherKey] as? Int == 8)
precondition(object[equalKey] as? Int == 9)
precondition(String(describing: Payload.CodingKeys.value).contains("wire_value"))
precondition(String(describing: Payload.CodingKeys.other).contains("other"))
precondition(String(reflecting: Payload.CodingKeys.equal).contains("equal"))
let decoded = try JSONDecoder().decode(Payload.self, from: data)
precondition(decoded == original)
