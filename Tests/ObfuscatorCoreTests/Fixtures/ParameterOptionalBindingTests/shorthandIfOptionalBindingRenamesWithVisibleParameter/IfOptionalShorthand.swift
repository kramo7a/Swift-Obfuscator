func inspect(_ value: Int?) -> Int {
    if let value { return value }
    return value ?? 0
}
