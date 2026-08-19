private enum ExplicitWire: String {
    case implicit
    case stable = "wire_stable"
}
precondition(ExplicitWire.implicit.rawValue == ["im", "plicit"].joined())
precondition(ExplicitWire.stable.rawValue == "wire_stable")
