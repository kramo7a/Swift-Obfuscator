import Foundation
enum Word: String {
    case alpha
    case beta
}
enum Number: Int {
    case zero
    case two = 2
    case three
}
enum Reflected: String {
    case visible
}
struct Payload: Codable {
    let value: Int
    enum CodingKeys: String, CodingKey { case value }
}
precondition(Word.alpha.rawValue == ["a", "l", "p", "h", "a"].joined())
precondition(Word.beta.rawValue == ["b", "e", "t", "a"].joined())
precondition(Number.zero.rawValue == 0)
precondition(Number.three.rawValue == 3)
_ = "value=\(Reflected.visible)"
let data = try JSONEncoder().encode(Payload(value: 7))
precondition(String(data: data, encoding: .utf8) == "{\"value\":7}")
