func inspect(_ value: Int?) -> Int {
    guard let value = value, value > 0 else { return 0 }
    return value
}
