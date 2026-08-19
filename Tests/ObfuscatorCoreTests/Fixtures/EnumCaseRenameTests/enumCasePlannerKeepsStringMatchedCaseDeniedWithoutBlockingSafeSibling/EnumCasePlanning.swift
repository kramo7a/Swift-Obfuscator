private enum Safe {
    case idle
    case payload(value: Int)

    static func normalize(_ input: Self) -> Self {
        switch input {
        case .idle:
            return .payload(value: 1)
        case .payload:
            return .idle
        }
    }
}

private enum Blocked {
    case logged
    case queued(value: Int)

    static func sample() -> Self {
        .queued(value: 2)
    }
}

private let blockedWire = "logged"
