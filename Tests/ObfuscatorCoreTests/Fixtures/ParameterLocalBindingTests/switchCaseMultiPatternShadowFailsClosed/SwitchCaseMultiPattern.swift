enum Focus { case standard; case first(Int); case second(Int) }
func route(_ value: Int, focus: Focus) -> Int {
    switch focus {
    case .first(let value), .second(let value): return value
    case .standard: return value
    }
}
