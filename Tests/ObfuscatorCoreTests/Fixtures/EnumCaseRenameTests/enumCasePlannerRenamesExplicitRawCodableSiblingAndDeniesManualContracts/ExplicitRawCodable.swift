import Foundation
private enum StableWire: String, Codable {
    case first = "wire_first"
    case second = "wire_second"
}
private enum ImplicitWire: String, Codable {
    case first
    case second = "wire_second"
}
private enum CustomWire: String, Codable {
    case visible = "wire_visible"
    case hidden = "wire_hidden"
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode("custom-" + String(describing: self))
    }
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = value == "custom-visible" ? .visible : .hidden
    }
}
let encoded = try JSONEncoder().encode(StableWire.first)
precondition(String(data: encoded, encoding: .utf8) == "\"wire_first\"")
private let decoded = try JSONDecoder().decode(
    StableWire.self,
    from: Data("\"wire_second\"".utf8)
)
precondition(decoded == .second)
precondition(ImplicitWire.first.rawValue == ["fi", "rst"].joined())
precondition(ImplicitWire.second.rawValue == "wire_second")
