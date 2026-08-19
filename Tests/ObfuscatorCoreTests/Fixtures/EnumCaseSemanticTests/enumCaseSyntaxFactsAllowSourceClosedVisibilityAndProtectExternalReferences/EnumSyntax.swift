private enum Safe {
    case idle
    case payload(value: Int)
    static func match(_ value: Safe) {
        switch value {
        case .idle: break
        case .payload: break
        }
    }
}
private enum Reflected {
    case logged
}
let reflectedText = "\(Reflected.logged)"
let reflectedWire = "logged"
public enum Visible {
    case shown
}
@available(*, deprecated)
private enum Attributed {
    case marked
}
private enum Conforming: Equatable {
    case equal
}
public enum Escaping {
    case exported
}
