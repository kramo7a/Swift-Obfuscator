protocol Factory {
    static var idle: Self { get }
    static func payload(value: Int) -> Self
}
enum Witness: Factory {
    case idle
    case payload(value: Int)
}
enum Ordinary: Equatable {
    case idle
    case other
}
