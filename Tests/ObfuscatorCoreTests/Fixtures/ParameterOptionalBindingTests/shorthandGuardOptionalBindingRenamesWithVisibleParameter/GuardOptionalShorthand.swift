func inspect(_ value: Int?) -> Int {
    guard let value, value > 0 else { return value ?? 0 }
    return value
}
