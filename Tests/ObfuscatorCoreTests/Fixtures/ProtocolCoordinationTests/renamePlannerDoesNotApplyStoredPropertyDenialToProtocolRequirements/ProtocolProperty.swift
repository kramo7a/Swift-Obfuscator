protocol Payload {
    var value: Int
        { get }
}
struct Model: Payload { var value: Int { 42 } }
